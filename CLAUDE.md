# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

Moodwalk is a Rails 8 app that generates short walking routes ("journeys") near a user's
location — a loop or a one-way trip, whichever the real nearby places support — and lets users
start/complete a "walk" along one, with live turn-by-turn guidance and GPS tracking during the
walk, logging mood and reflection afterward. Routes are geospatial (PostGIS); route geometry comes
from the Mapbox Directions API, and real waypoints come from the Google Places API.

## Commands

- Setup: `bin/setup` (installs gems, prepares the DB; `--reset` resets DB, `--skip-server` skips starting the server)
- Run dev server: `bin/dev` (thin wrapper around `bin/rails server`)
- Run all tests: `bin/rails test`
- Run a single test file: `bin/rails test test/models/walk_test.rb`
- Run a single test: `bin/rails test test/models/walk_test.rb -n test_method_name` (or `TEST=path LINE=n`)
- Lint: `bin/rubocop` (uses `rubocop-rails-omakase` base config, see `.rubocop.yml` for overrides)
- Security scan: `bin/brakeman`
- Gem vulnerability audit: `bin/bundler-audit`
- Full CI pipeline (what CI actually runs, in order): `bin/ci` — runs setup, rubocop, bundler-audit,
  `bin/importmap audit`, brakeman, `bin/rails test`, then `db:seed:replant` in `RAILS_ENV=test` as a
  smoke test of `db/seeds.rb`. See `config/ci.rb`.
- Seed the dev DB (also calls out to the live Mapbox API): `bin/rails db:seed`
- Backfill missing journey neighborhood labels: `bin/rails journeys:backfill_location_names`
  (one-off; `Journey#location_name` no longer geocodes lazily on read)

GitHub Actions runs the same checks on push/PR (`.github/workflows/ci.yml`): a lint job
(rubocop/brakeman/audits) and a test job against a `postgis` service container. The seed smoke test
runs only on pushes, since it needs the real `MAPBOX_ACCESS_TOKEN` secret.

**`bin/ci` is not the whole pipeline.** `bin/rails test` does not include `test/system`, and the
`Tests: System` step in `config/ci.rb` is commented out — so system tests pass CI but never run
locally via `bin/ci`. The workflow runs them as their own step, as
`bin/rails test:system || bin/rails test:system`: headless Chrome intermittently reports a click it
never delivers to the page, with no exception and the element connected and unobstructed (see
`click_and_confirm` in `test/application_system_test_case.rb` for what was ruled out). A genuinely
broken button still fails, because it fails both times. Failure screenshots upload as an artifact. Pre-existing structural
rubocop offenses are tracked in `.rubocop_todo.yml` — remove entries as files are refactored rather
than adding new ones.

Requires a `MAPBOX_ACCESS_TOKEN` env var (see `.env`, loaded via `dotenv-rails` in dev/test) for
anything that generates journeys (seeding, `JourneyGenerator`). Requires a `GOOGLE_PLACES_API_KEY`
env var for real POI-based route generation from the app (`PoiFinder`) — not used by seeding. The
LLM features read `GEMINI_API_KEYS`; see **LLM usage** below.

`dotenv-rails` loads `.env` in the **test** environment too, so any key the suite does not pin
arrives holding a real credential. `test/test_helper.rb` pins each one by name and
`test/credentials_pinned_test.rb` fails if one is missed — a new key in `.env` needs adding to both.
Both halves of that have already gone wrong here: the suite ran on production Gemini keys because
only the singular `GEMINI_API_KEY` was pinned while `LlmChat#keys` reads `GEMINI_API_KEYS` first,
and `MAPBOX_ACCESS_TOKEN` went unpinned while every map view renders it into the page. That test
asserts with bare `assert` and hand-written messages on purpose: a failing `assert_equal` would
print the live credential into CI logs on the one run that proves it is exposed.

Database is PostgreSQL with the `postgis` adapter (`activerecord-postgis-adapter` /
`rgeo`) — do not swap in a plain `pg` adapter or plain lat/lng columns for geospatial data.

## Architecture

**Domain model**: `User` -> has many `Walk`s. `Journey` -> has many `Walk`s. `User` <-> `Journey`
also join through `SavedJourney` (bookmarks; `user.saved_routes` / `journey.saved_by?(user)`), and a
`Walk` has many `WalkTrackPoint`s (raw GPS breadcrumbs, collapsed into `Walk#actual_path` on
completion). A `Journey` is a pre-generated walking route (polyline + distance/duration estimate),
either a loop or one-way, anchored at a `start_point` (PostGIS `geography` point). A `Walk` is one user's attempt at a
`Journey` (`started_at`/`completed_at`, plus post-walk `mood_after`/`reflection`/actuals).

**Route generation, real POI-based (`RouteBuilder` -> `PoiFinder` -> `PoiSelector` ->
`ShortlistRouter` -> `JourneyGenerator` -> `RouteDescriber`)**: `RouteBuilder` is the theme-picker
entry point. Note the order: describing runs **last**, deliberately. More than one route is routed
per build, so describing before routing would pay for descriptions of routes that are thrown away.
`PoiFinder` asks Google Places API (New) Nearby Search for real nearby places by **primary** type
(`includedPrimaryTypes` — `includedTypes` matched any tag, and returned a bar as a hiking area) (one
call per category in the theme's `categories` list, see `config/initializers/themes.rb` — the
category slugs there are Google's published "Table A" place types, not Mapbox's). `PoiSelector` is
plain Ruby (no HTTP/LLM call) that picks 2-4 of those candidates as waypoints, and returns the rest
of its shortlist as `alternatives`. It plans lengths as straight-line tour × `DETOUR_FACTOR` (1.4,
measured on real Mapbox routes at 1.22-1.61) — on straight lines alone, walks came back ~40% longer
than the duration picked. Scoring priority
when a target distance exists: distance-fit first (grouped into coarse bands via
`DISTANCE_BAND_RATIO` — a category-diverse combination is not allowed to override the duration the
user actually picked), then loop roundness, then category diversity, then exact distance as a
final tiebreak; with no target, roundness leads, then diversity, then compactness. "Roundness" is
the isoperimetric quotient (4πA/P², 0-1) of the polygon start → waypoints → start, in visiting
order: 0 for any loop that walks back the way it came *or* back through the start between
waypoints. It replaced "bearing spread", which rewarded waypoints on opposite sides of the start
most of all — the route between them runs back through the start, and real routes built that way
re-walked up to 40% of their length. A loop combination below `MIN_LOOP_ROUNDNESS` (0.3) isn't
offered as a loop at all — ranked by distance first, one used to beat a round loop further down
the shortlist. `RouteDescriber` writes the route's atmospheric description for the
already-chosen waypoints — it does not pick them, and it has **two modes**. `RouteDescriber.fallback_for`
is plain Ruby and runs inside the request, so every journey is saved with a description and none is
ever blank; the LLM version (via `ruby_llm`/`ruby_llm-schema`) runs afterwards in
`JourneyDescriptionJob` and replaces that text. Each stage returns its own `Result` struct and `RouteBuilder` stops at the first that fails, surfacing
that stage's error.

**Choosing between routes (`ShortlistRouter`, `RouteOverlap`)**: whether a route is the right
length and whether it retraces its own streets only show in the route Mapbox returns — a spur in and
out of a park never appears in the waypoint plan. So `ShortlistRouter` routes the selector's pick,
then its alternatives, and accepts the first whose **Mapbox duration** (the minutes the app shows,
which allow for crossings — measured at 68-77 m/min against the 80 planned with) is within
`RouteBuilder::TOLERANCE_RATIO` (25%) of the time picked and that re-walks no more than
`MAX_OVERLAP_RATIO` (10%) of itself, up to `MAX_ROUTINGS` (3) Mapbox calls; if none passes, the
right length wins over less retracing, then the closest length. Loop vs. one-way is decided per
request, not a coin flip, and **after** routing: `RouteBuilder` routes the loop shortlist first (if
the places make a loop worth walking) and, only if its choice fails either check, the one-way
shortlist too, keeping whichever ranks better — whether a loop retraces itself only shows once
Mapbox has routed it. `RouteOverlap` measures
the retracing (`Journey#overlap_ratio`): the share of the route lying within a street's width of
ground walked more than 30m earlier. With a duration, `RouteBuilder` searches once, as far as a
one-way walk of that length can reach (target ÷ `DETOUR_FACTOR`), and **never wider**: measured
across three areas, every route built from a wider search came back 30-60 minutes long for a
20-minute request. Only "no rush" (no duration) widens a failed pass, doubling the radius up to
`MAX_ATTEMPTS`; across all passes a build makes at most `MAX_ROUTINGS_PER_BUILD` (6) Mapbox calls.
`JourneysController` refuses any duration the picker doesn't offer (`DURATION_CHOICES`) before
searching — 0 used to mean a zero radius and a division by zero. When no route can be built, `JourneysController#fallback_journey` reuses a saved
route via `ReusableWalk` (same theme and time, starting within 300m, passing the retrace check), or
else sends the user home with an honest notice — it no longer swaps in another theme or the newest
route anywhere. If Google or Mapbox couldn't be reached (`RouteBuilder::Result#unavailable`), the
notice says so instead of claiming nothing is nearby; the wording lives in `NoWalkNotice`. The notice names only themes `ThemeSuggestions` has **checked from that spot**: a
reusable saved walk (free) or, failing that, `PoiFinder#enough_nearby?` — one grouped Places request
for the whole theme, at the same reach `RouteBuilder` searches (`WalkReach.search_radius`) — stopping
at two themes. `RouteBuilder` used to search again
at a rescaled radius whenever the length was off, too: a full set of category calls
per retry (~14 Places calls a route, measured), and it rarely fixed the length, since the selector
aimed at the same target from much the same places. The start is reverse-geocoded once per build
and handed to `JourneyGenerator` as `location_name:`, not once per route routed.

**Route generation, synthetic loop (`app/services/journey_generator.rb`)**: `JourneyGenerator`
talks to Mapbox Directions. Given real waypoints (from `PoiSelector`) it just routes through them;
given none (and a target distance instead — used by `db/seeds.rb`, which doesn't go through
`RouteBuilder`), it plants 4 synthetic waypoints roughly evenly around a circle (bearings
0/90/180/270 + jitter) whose radius approximates the target loop circumference. If the returned
distance is outside `TOLERANCE_RATIO` (15%) of the target, it rescales the radius by the inverse of
the distance ratio and retries, up to `MAX_ATTEMPTS`. For themed routes, a u-turn maneuver in the
response is treated as an invalid dead-end *unless* it's near one of the real waypoints (a spur
down a dead-end path to reach a POI is expected to u-turn there). Returns a `Result` struct
(`success?`, `journey`, `error`, `unavailable`) rather than raising — callers must check `success?`
before using `journey`. `unavailable` marks Mapbox itself failing (timeouts, refused connections,
5xx, 401/403/429) as opposed to no walkable route; these used to raise out of the request as a 500.
`RouteBuilder` stops calling Mapbox after the first one and doesn't widen its search. The Mapbox and Google Places calls are synchronous (via Faraday), inside the request.
`MapboxGeocoder` and `LocationsController` also call Mapbox separately, for reverse/forward
geocoding — Mapbox isn't only used by `JourneyGenerator`.

**In-walk navigation (`app/javascript/controllers/walking_controller.js`)**: once a walk starts,
this Stimulus controller gives live turn-by-turn guidance from `Journey#turn_waypoints` (Mapbox
route steps simplified into left/right/end nodes) by watching `navigator.geolocation.watchPosition`,
and separately buffers/POSTs GPS breadcrumbs (`WalkTrackPoint`, via `WalksController#track`) so the
actually-walked path can be shown against the suggested route afterward. Arrival detection checks
the segment between consecutive GPS fixes against each upcoming waypoint (bounded to
`MAX_WAYPOINT_LOOKAHEAD` waypoints ahead), not just the latest fix's distance to the current
target — a big jump between fixes (real GPS gaps/lag, or fast movement) can otherwise skip clean
over a short leg without the fix ever landing inside its arrival radius, permanently stalling
guidance on a waypoint already passed. Has a dev-mode walk simulator
(`?simulate=<speed multiplier>` on a walk's show page, gated by `Rails.env.development?`) that
fakes movement along the route, useful for testing guidance without physically walking it.

**Background jobs (`app/jobs`)**: the two LLM calls that used to sit inside a request now run
off it, on Solid Queue in production. Both follow the same pattern — a plain-Ruby fallback is
written synchronously so there is always something true on screen, and the job replaces it with
better text when the model answers. `JourneyDescriptionJob` was moved out because the LLM was two
thirds of a route's build time (~3s of ~4.5s, measured); `JourneyHighlightsJob` because opening a
journey fired an XHR that sat on a ~12-second call with the list on screen empty
(`JourneyHighlights` is its plain-Ruby counterpart, derived from the route's categories). Both
`discard_on ActiveJob::DeserializationError` — the journey can be gone by the time they run. Both
are enqueued from `JourneysController`.

**Shared helpers**: `RouteGeometry` (`app/services/route_geometry.rb`) owns a route's shape — the
decoded polyline, the loop check and the turn list — and `Journey` delegates all three to it; it
needs nothing from the record but the polyline, and the decode is memoized because `loop?` alone
asks for it twice. `GeoDistance` (`app/services/geo_distance.rb`) owns the great-circle math —
`haversine`, `bearing`, `destination_point` — and `PolylineDecoder` owns encoded-polyline decoding;
use these rather than re-deriving the formulas (they were previously duplicated across `Journey`,
`PoiSelector` and `JourneyGenerator`). `ExternalApi` (`app/services/external_api.rb`) builds the
Faraday connection for every third-party call, so they all carry timeouts — route new HTTP calls
through it. `Walk` owns **two** single-source-of-truth pace constants, and both exist because the app
disagreed with itself without them. `STEP_LENGTH_METERS` (0.76) is mirrored deliberately in
`walking_controller.js`; planned and actual step counts must divide by the same number or every
walk reports a step delta it did not have. `WALKING_METERS_PER_SECOND` (80/60) is read by
`RouteBuilder` — via `Walk.walking_meters_per_minute` — to turn a picked duration into a target
distance, and passed to Mapbox by `JourneyGenerator` as the `walking_speed` param so its duration
estimate uses the same pace. Mapbox's own default is 1.42 m/s, which is why a walk planned for
thirty minutes used to come back described as twenty-eight.

**Geospatial queries**: `Journey.near(lat, lng, radius_meters)` (`app/models/journey.rb`) does the
PostGIS proximity query (`ST_DWithin` + distance ordering) — build lat/lng-radius searches on this
scope rather than hand-rolling new geospatial SQL. The `ORDER BY` is built via `sanitize_sql_array` rather
than interpolated, because `Arel.sql` switches off Rails' injection guard — keep it that way if you
extend the scope.

**Routing/controllers**: `JourneysController` exposes only `create` plus member `save`/`highlights`;
journeys are otherwise reached as a nested resource under a walk's creation flow
(`/journeys/:journey_id/walks/new|create`) — there is no journeys index/show. `CommunityRoutesController`
(`index`/`show`) is the browse surface, scoped through the `Journey.community` scope.
`WalksController` exposes `show`, `index`, `edit`, `update` and members `complete`, `attach_photo`,
`share`, `track`, `share_quote`, `memory`. **All walk lookups outside `create` are scoped through
`current_user.walks`** (never bare `Walk.find`) — preserve that scoping when adding actions; a bare
`Walk.find` in `share_quote` was a cross-user read/write hole, and
`test/controllers/walks_controller_test.rb` now guards it. `ApplicationController` requires
authentication (Devise `authenticate_user!`) on every action by default; controllers that need to be
public must explicitly `skip_before_action :authenticate_user!`. `PagesController#home` skips it only
to send signed-out visitors to the login form without Devise's "You need to sign in" warning.

**Auth**: Devise (`database_authenticatable, registerable, recoverable, rememberable, validatable`)
on `User`. Sign-up/account-update permit an extra `name` param via
`configure_permitted_parameters` in `ApplicationController` — extend that method (not a Devise
override) if new fields are added to registration.

**Frontend**: Server-rendered ERB views + Bootstrap 5 (via the `bootstrap` gem/Sass, not a CDN) +
Sprockets asset pipeline (`sassc-rails`) + Hotwire (Turbo + Stimulus) + importmap (no
Node/webpack/yarn build step). Forms use `simple_form`. Stimulus controllers live in
`app/javascript/controllers/`.

**LLM usage**: the `ruby_llm` / `ruby_llm-schema` gems back three prose generators —
`RouteDescriber` (`app/services/route_describer.rb`, each route's description),
`JourneyHighlightsGenerator` and `ShareQuoteGenerator`. All three follow the same shape:
`LlmChat.with_chat { |chat| chat.with_instructions(...).with_schema(...).ask(...) }`. They never
call `RubyLLM.chat` directly, so model and provider are a one-file change in `LlmChat`
(`app/services/llm_chat.rb`), which pins `gemini-3.5-flash` on `:gemini`. Credentials come from
`GEMINI_API_KEYS` — a comma-separated list `LlmChat.keys` falls through when a key hits its quota,
with singular `GEMINI_API_KEY` as a fallback. The `anthropic_api_key` / `openai_api_key` lines in
`config/initializers/ruby_llm.rb` are spare credentials for providers the app is **not** pointed
at; don't infer the provider from them.

## Notes

- Model/attribute naming has shifted: "routes" were renamed to "journeys" via migration
  `db/migrate/20260825012336_rename_routes_to_journeys.rb`. The stale `test/models/route_test.rb`
  and the dead `RoutesController` (which called a `pending_journeys` table dropped in
  `db/migrate/20260831110924_drop_pending_journeys.rb`) have both been removed.
- `bin/ci`'s seed-replant step means `db/seeds.rb` must stay runnable (and idempotent) against a
  real Mapbox token in CI.
- **A journey's card imagery is a hard-coded URL table.** `JourneyImages` holds thirteen
  hand-copied Google-hosted photo URLs — lifted out of `Journey` because it was a sixth of the model
  by RuboCop's count, not because the approach is right. Nothing here requests these properly, so
  they carry none of the attribution Google Places Photos requires. Replacing them (Places Photos
  with attribution, or a Mapbox static image of the route itself) is its own piece of work.
- **The walker counts and star ratings on community route cards are invented.** `PlaceholderStats`
  derives them from the primary key so a given route always shows the same numbers. `Journey#walker_count`
  and `#rating` — the real figures — still exist and are still tested, but only one walk in the
  database carries a rating, so the real numbers leave almost every card blank. This is temporary
  by design: switching over is two views (`community_routes/index` and `show`) and then deleting the
  file. Treat it as a known temporary, not as architecture, and don't report those numbers as real
  anywhere outside the app.
- `test/fixtures` has `users`/`journeys`/`walks` fixtures (the `journeys` one writes its PostGIS
  `start_point` as EWKT). `webmock` stubs all outbound HTTP — a test that unexpectedly hits the
  network fails loudly, which is what keeps `Journey#location_name` honest about not geocoding on
  read. Coverage is broad: every controller has a test file (`PagesController` since #184), as do
  the jobs and most models and services; `test/system/getting_a_walk_test.rb` drives a real browser
  through generating and walking a route. **Without a test file of their own:** the services
  `RouteGeometry`, `JourneyHighlights`, `JourneyImages` and `PlaceholderStats`, the model
  `WalkTrackPoint`, and the helpers — some are exercised through other classes' tests. Keep that list
  true rather than letting it rot into a lie again, and remember system tests need
  `bin/rails test:system` (see the `bin/ci` note above).
