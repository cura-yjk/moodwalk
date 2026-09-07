# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

Moodwalk is a Rails 8 app that generates short walking-loop routes ("journeys") near a user's
location and lets users start/complete a "walk" along one, logging mood and reflection afterward.
Routes are geospatial (PostGIS), and route geometry comes from the Mapbox Directions API.

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

Requires a `MAPBOX_ACCESS_TOKEN` env var (see `.env`, loaded via `dotenv-rails` in dev/test) for
anything that generates journeys (seeding, `JourneyGenerator`). Requires a `GOOGLE_PLACES_API_KEY`
env var for real POI-based route generation from the app (`PoiFinder`) — not used by seeding.

Database is PostgreSQL with the `postgis` adapter (`activerecord-postgis-adapter` /
`rgeo`) — do not swap in a plain `pg` adapter or plain lat/lng columns for geospatial data.

## Architecture

**Domain model**: `User` -> has many `Walk`s. `Journey` -> has many `Walk`s. A `Journey` is a
pre-generated walking loop route (polyline + distance/duration estimate) anchored at a
`start_point` (PostGIS `geography` point). A `Walk` is one user's attempt at a `Journey`
(`started_at`/`completed_at`, plus post-walk `mood_after`/`reflection`/actuals).

**Route generation, real POI-based (`RouteBuilder` -> `PoiFinder` -> `PoiSelector` ->
`RouteDescriber` -> `JourneyGenerator`)**: `RouteBuilder` is the theme-picker entry point.
`PoiFinder` asks Google Places API (New) Nearby Search for real nearby places by category (one
call per category in the theme's `categories` list, see `config/initializers/themes.rb` — the
category slugs there are Google's published "Table A" place types, not Mapbox's). `PoiSelector` is
plain Ruby (no HTTP/LLM call) that picks 2-4 of those candidates as waypoints, scoring
combinations by category diversity then by how close a walking-order tour comes to any target
distance. `RouteDescriber` (via the `ruby_llm`/`ruby_llm-schema` gems) writes the route's
atmospheric description for the already-chosen waypoints — it does not pick them. Each stage
returns its own `Result` struct and `RouteBuilder` stops at the first that fails, surfacing that
stage's error. When a target duration is given, `RouteBuilder` widens/rescales its POI search
radius and retries (its own `MAX_ATTEMPTS`/`TOLERANCE_RATIO`), same idea as `JourneyGenerator`'s
own retry below.

**Route generation, synthetic loop (`app/services/journey_generator.rb`)**: `JourneyGenerator`
talks to Mapbox Directions. Given real waypoints (from `PoiSelector`) it just routes through them;
given none (and a target distance instead — used by `db/seeds.rb`, which doesn't go through
`RouteBuilder`), it plants 4 synthetic waypoints roughly evenly around a circle (bearings
0/90/180/270 + jitter) whose radius approximates the target loop circumference. If the returned
distance is outside `TOLERANCE_RATIO` (15%) of the target, it rescales the radius by the inverse of
the distance ratio and retries, up to `MAX_ATTEMPTS`. For themed routes, a u-turn maneuver in the
response is treated as an invalid dead-end *unless* it's near one of the real waypoints (a spur
down a dead-end path to reach a POI is expected to u-turn there). Returns a `Result` struct
(`success?`, `journey`, `error`) rather than raising — callers must check `success?` before using
`journey`. These are synchronous HTTP calls (via Faraday); there's no background job for them yet.
`MapboxGeocoder` and `LocationsController` also call Mapbox separately, for reverse/forward
geocoding — Mapbox isn't only used by `JourneyGenerator`.

**Geospatial queries**: `Journey.near(lat, lng, radius_meters)` (`app/models/journey.rb`) does the
PostGIS proximity query (`ST_DWithin` + distance ordering) — build lat/lng-radius searches on this
scope rather than hand-rolling new geospatial SQL. Note the raw SQL interpolates `lng`/`lat` directly
into the `ORDER BY` clause (not parameterized) — if reusing that pattern elsewhere with user input,
parameterize it instead.

**Routing/controllers**: Journeys are only ever accessed as a nested resource under a `walk`'s
creation flow (`/journeys/:journey_id/walks/new|create`); there is no top-level journeys index/show
route or controller. `WalksController` otherwise exposes `show`, `index`, `edit`, `update`, and a
member `complete` action. All walk lookups outside `create` are scoped through `current_user.walks`
(never bare `Walk.find`) — preserve that scoping when adding actions. `ApplicationController`
requires authentication (Devise `authenticate_user!`) on every action by default; controllers that
need to be public must explicitly `skip_before_action :authenticate_user!` (see
`PagesController#home`).

**Auth**: Devise (`database_authenticatable, registerable, recoverable, rememberable, validatable`)
on `User`. Sign-up/account-update permit an extra `name` param via
`configure_permitted_parameters` in `ApplicationController` — extend that method (not a Devise
override) if new fields are added to registration.

**Frontend**: Server-rendered ERB views + Bootstrap 5 (via the `bootstrap` gem/Sass, not a CDN) +
Sprockets asset pipeline (`sassc-rails`) + Hotwire (Turbo + Stimulus) + importmap (no
Node/webpack/yarn build step). Forms use `simple_form`. Stimulus controllers live in
`app/javascript/controllers/`.

**LLM usage**: the `ruby_llm` / `ruby_llm-schema` gems are wired into `RouteDescriber`
(`app/services/route_describer.rb`), which writes each route's description using
`RubyLLM.chat.with_schema(...)`. It's the only LLM call in the app — don't assume broader LLM
integration exists beyond it. Requires `OPENAI_API_KEY` (see `config/initializers/ruby_llm.rb`).

## Notes

- Model/attribute naming has shifted recently: "routes" were renamed to "journeys" via migration
  `db/migrate/20260825012336_rename_routes_to_journeys.rb`; a stale `test/models/route_test.rb`
  still references the old name and should be renamed/updated, not treated as current.
- `bin/ci`'s seed-replant step means `db/seeds.rb` must stay runnable (and idempotent) against a
  real Mapbox token in CI.
