# Category slugs below are Google Places API (New) "Table A" types, verified
# against the live docs at
#   https://developers.google.com/maps/documentation/places/web-service/place-types
# Before adding a new one, check it's actually listed there for use with
# includedTypes - not every plausible-sounding type exists (e.g. there's no
# generic "waterfront" type; the closest real options were used instead, and
# anything with no reasonable match was left out rather than forced onto an
# unrelated type).
#
# Deliberately left out, even though they're real Table A types: louder or
# more commercial categories like amusement_park, casino, night_club,
# video_arcade, shopping_mall, department_store - they clash with the app's
# quiet, non-commercial, sensory tone (see RouteDescriber's system prompt).
THEMES = {
  calm: {
    label: "Calm",
    subtitle: "Quiet your mind, one step at a time",
    icon: "fa-solid fa-cloud",
    # Added city_park/garden/nature_preserve/lake alongside the original
    # three - teammate, take a look and trim if any feel off-theme:
    # - city_park: gentler-scale alternative to national_park for a "quiet"
    #   walk (a big national park search radius can feel like overkill).
    # - garden: turns out to be its own real type, not just botanical_garden.
    # - nature_preserve: closer to the original Mapbox-era "nature reserve"
    #   idea than stretching national_park to cover it.
    # - lake: may return few/no results in a dense city - harmless if so,
    #   PoiFinder just skips categories with nothing nearby.
    categories: ["park", "botanical_garden", "national_park", "city_park", "garden", "nature_preserve", "lake"],
    tone: "quiet, unhurried, and settled — emphasize low traffic, " \
          "greenery or water, and a slower, gentler pace"
  },
  refresh: {
    label: "Refresh",
    subtitle: "Energize your body and mind",
    icon: "fa-solid fa-droplet",
    # Added observation_deck/mountain_peak/marina - teammate, worth a look:
    # - observation_deck: a real, much closer match for "scenic viewpoint"
    #   than anything we had before.
    # - mountain_peak: fits "energizing/scenic," but likely sparse or absent
    #   in flat/urban areas - same "harmless if empty" caveat as above.
    # - marina: open waterfront energy, distinct from a plain beach.
    categories: ["beach", "scenic_spot", "observation_deck", "mountain_peak", "marina"],
    tone: "open and energizing — emphasize fresh air, a scenic outlook, " \
          "and a slightly brisker, more awake pace"
  },
  cheerful: {
    label: "Cheerful",
    subtitle: "Find a little delight nearby",
    icon: "fa-solid fa-sun",
    # Added market/cafe/ice_cream_shop/dessert_shop - teammate, your call:
    # - market: turns out to be its own real, general type (not just
    #   farmers_market/flea_market) - closer to the original "market" vibe.
    # - cafe, ice_cream_shop, dessert_shop: small, colorful, low-key treats
    #   in the same spirit as bakery - drop any that feel too food-focused.
    categories: ["farmers_market", "flea_market", "market", "bakery", "playground", "cafe", "ice_cream_shop",
                 "dessert_shop"],
    tone: "bright and light — emphasize color, everyday liveliness, " \
          "and small moments of delight along the way"
  },
  recharge: {
    label: "Recharge",
    subtitle: "Slow down and restore",
    icon: "fa-solid fa-leaf",
    # Added nature_preserve/wildlife_refuge/woods/picnic_ground - teammate,
    # feel free to prune: all four lean further into "deep, restorative,
    # away from noise" than the original three alone.
    categories: ["national_park", "hiking_area", "campground", "nature_preserve", "wildlife_refuge", "woods",
                 "picnic_ground"],
    tone: "deep and restorative — emphasize dense greenery, distance " \
          "from noise, and enough length to truly unwind"
  }
}.freeze
