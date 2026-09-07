# Moodwalk

Moodwalk is an app that suggests short walking routes ("journeys") near wherever you are, and lets
you go for a "walk" along one of them. After you finish, you log how you're feeling and write a
short reflection.

## What it's built with

- **Ruby on Rails** (version 8) — the web framework the whole app is built on.
- **PostgreSQL with PostGIS** — our database, with an extra add-on (PostGIS) that lets it understand
  locations, distances, and map shapes, not just plain numbers and text.
- **Mapbox Directions API** — an outside service we call to get real walking directions and turn
  them into a route on a map.
- **Devise** — handles sign up, log in, log out, and password resets, so we don't have to build that
  from scratch.
- **Hotwire (Turbo + Stimulus) and Bootstrap** — these make pages feel responsive and look decent
  without us writing a lot of custom JavaScript or CSS.
- **simple_form** — a helper for building HTML forms more easily.

You don't need to be an expert in any of these to contribute — the setup steps below get you
running without deep knowledge of what's happening under the hood.

## Glossary — what kind of thing each of these is

If the list above still reads like a wall of proper nouns, here's the general vocabulary:

- **Programming language** — the language the actual code is written in. Ours is **Ruby**.
- **Framework** — a big pre-built toolkit for building a certain kind of app, so you're not
  starting from zero. **Rails** is a framework for building web apps in Ruby. "8" is just the
  version number.
- **Database** — where the app's data actually lives long-term (users, journeys, walks, etc.),
  like a very powerful, structured spreadsheet. Ours is **PostgreSQL**.
- **Database extension** — an add-on that gives a database new abilities. **PostGIS** is an
  extension for PostgreSQL that teaches it to understand map locations and distances, which a
  plain database can't do on its own.
- **Gem / library** — a chunk of reusable code someone else wrote that we plug into our app instead
  of writing ourselves. **Devise** (login/signup), **Hotwire**/**Turbo**/**Stimulus** (snappier
  pages with less custom JavaScript), and **simple_form** (easier HTML forms) are all gems.
- **CSS framework** — a library of ready-made visual styles (buttons, forms, spacing) so pages look
  decent without designing every pixel by hand. That's **Bootstrap**.
- **Third-party API / service** — a completely separate company's product that our app talks to
  over the internet to get something it can't do itself. **Mapbox** is not part of our codebase at
  all — we send it a request (e.g. "give me walking directions between these points") and it sends
  data back.

Roughly: language → framework → database (+ extensions) → gems/libraries, with one outside
service (Mapbox) bolted on for maps.

## The basic idea (data model)

Three main things in the app, and how they relate:

- **User** — someone with an account. A user can go on many walks.
- **Journey** — a pre-made walking route: a loop that starts and ends at the same spot, with an
  estimated distance and time. Many users can each do their own walk along the same journey.
- **Walk** — one specific attempt by one user at one journey: when they started, when they
  finished, and afterward, their mood and a written reflection.

Behind the scenes, `app/services/journey_generator.rb` is the piece of code that talks to Mapbox to
turn a set of points into an actual walking route. Those points either come from real nearby
places — `app/services/poi_finder.rb` asks Google Places for parks, bakeries, and similar spots
near the user, and `app/services/poi_selector.rb`/`app/services/route_describer.rb` pick a few of
them and write a short description — or, when there aren't enough real places nearby, a synthetic
loop shape. If the resulting route is too short or too long, it adjusts and tries again.

## Getting it running on your machine

You'll need PostgreSQL installed with the PostGIS extension available (this is what lets the
database handle map locations).

```bash
bin/setup            # installs everything the app needs and sets up the database
bin/setup --reset    # same, but wipes and rebuilds the database from scratch
```

Open the `.env` file and add these keys:

```
MAPBOX_ACCESS_TOKEN=your_token_here
GOOGLE_PLACES_API_KEY=your_google_places_api_key_here
```

Without the Mapbox token, anything that creates journeys (like seeding sample data) won't work —
the app needs it to ask Mapbox for real walking directions. The Google Places key is needed for
looking up real nearby places when generating a themed route from the app itself (seeding doesn't
use it). Getting a key means creating a Google Cloud project, enabling "Places API (New)", turning
on billing, and creating a server-side API key restricted to that API.

## Running the app day-to-day

```bash
bin/dev              # starts the app so you can view it in a browser
bin/rails db:seed    # fills the database with sample data (uses the real Mapbox API, so it needs the token above)
```

## Checking your work before opening a PR

```bash
bin/rails test                              # runs all the automated tests
bin/rails test test/models/walk_test.rb     # runs just one test file
bin/rubocop                                 # checks code style/formatting
bin/brakeman                                # scans for common security mistakes
bin/bundler-audit                           # checks our dependencies for known vulnerabilities
```

`bin/ci` runs everything above, plus a couple of extra checks, in one go — it's the same thing our
CI pipeline runs automatically, so running it locally first can save you a round trip.

## Working together on this repo

- Create a new branch for whatever you're working on, and open a Pull Request (PR) into `master`
  when it's ready (or even partway done, as a "draft" PR, if you want early feedback).
- In the PR description, explain *why* you made the change, not just *what* you changed — that's
  the part that's hard to figure out later just by reading the code.
- Before opening a PR, run `bin/rubocop` and `bin/rails test` locally so you're not waiting on CI to
  tell you something's broken.
- [`CLAUDE.md`](CLAUDE.md) has more in-depth technical notes about the codebase — worth a skim if
  you want more detail than this file gives.
