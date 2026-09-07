# Category slugs below are Google Places API (New) "Table A" types, verified
# against the live docs at
#   https://developers.google.com/maps/documentation/places/web-service/place-types
# Before adding a new one, check it's actually listed there for use with
# includedTypes - not every plausible-sounding type exists (e.g. there's no
# generic "waterfront" or "market" type; the closest real options were used
# instead, and anything with no reasonable match was left out rather than
# forced onto an unrelated type).
THEMES = {
  calm: {
    label: "Calm",
    subtitle: "Quiet your mind, one step at a time",
    icon: "fa-solid fa-cloud",
    categories: ["park", "botanical_garden", "national_park"],
    tone: "quiet, unhurried, and settled — emphasize low traffic, " \
          "greenery or water, and a slower, gentler pace"
  },
  refresh: {
    label: "Refresh",
    subtitle: "Energize your body and mind",
    icon: "fa-solid fa-droplet",
    categories: ["beach", "scenic_spot"],
    tone: "open and energizing — emphasize fresh air, a scenic outlook, " \
          "and a slightly brisker, more awake pace"
  },
  cheerful: {
    label: "Cheerful",
    subtitle: "Find a little delight nearby",
    icon: "fa-solid fa-sun",
    categories: ["farmers_market", "flea_market", "bakery", "playground"],
    tone: "bright and light — emphasize color, everyday liveliness, " \
          "and small moments of delight along the way"
  },
  recharge: {
    label: "Recharge",
    subtitle: "Slow down and restore",
    icon: "fa-solid fa-leaf",
    categories: ["national_park", "hiking_area", "campground"],
    tone: "deep and restorative — emphasize dense greenery, distance " \
          "from noise, and enough length to truly unwind"
  }
}.freeze
