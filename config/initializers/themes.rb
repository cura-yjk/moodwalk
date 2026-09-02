# NOTE: category slugs below are drafts based on Mapbox's documented
# examples, not yet verified against the live endpoint. Before trusting
# them, check:
#   GET https://api.mapbox.com/search/searchbox/v1/list/category
# and confirm each slug here actually exists and returns results in
# your target area.
THEMES = {
  calm: {
    label: "Calm",
    subtitle: "Quiet your mind, one step at a time",
    icon: "fa-solid fa-cloud",
    categories: ["park", "garden", "nature_reserve"],
    tone: "quiet, unhurried, and settled — emphasize low traffic, " \
          "greenery or water, and a slower, gentler pace"
  },
  refresh: {
    label: "Refresh",
    subtitle: "Energize your body and mind",
    icon: "fa-solid fa-droplet",
    categories: ["beach", "viewpoint", "waterfront"],
    tone: "open and energizing — emphasize fresh air, a scenic outlook, " \
          "and a slightly brisker, more awake pace"
  },
  cheerful: {
    label: "Cheerful",
    subtitle: "Find a little delight nearby",
    icon: "fa-solid fa-sun",
    categories: ["market", "bakery", "playground"],
    tone: "bright and light — emphasize color, everyday liveliness, " \
          "and small moments of delight along the way"
  },
  recharge: {
    label: "Recharge",
    subtitle: "Slow down and restore",
    icon: "fa-solid fa-leaf",
    categories: ["nature_reserve", "hiking_trail", "campground"],
    tone: "deep and restorative — emphasize dense greenery, distance " \
          "from noise, and enough length to truly unwind"
  }
}.freeze
