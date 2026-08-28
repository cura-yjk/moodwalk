# NOTE: category slugs below are drafts from Mapbox's docs, not yet
# verified against the live endpoint. Before trusting them, check:
#   GET https://api.mapbox.com/search/searchbox/v1/list/category
# and confirm each slug here (waterfront, park, scenic_viewpoint, garden,
# market, plaza) actually exists and returns results in your target area.
THEMES = {
  nature_escape: {
    label: "Nature Escape",
    icon: "fa-solid fa-leaf",
    categories: ["waterfront", "park", "scenic_viewpoint"],
    tone: "peaceful, unhurried, and quiet — emphasize water, greenery, " \
          "open air, and a sense of slowing down"
  },
  peaceful_park: {
    label: "Peaceful Park",
    icon: "fa-solid fa-tree",
    categories: ["park", "garden"],
    tone: "calm and shaded — emphasize quiet park paths, dappled light, " \
          "and a gentle, introspective pace"
  },
  urban_refresh: {
    label: "Urban Refresh",
    icon: "fa-solid fa-building",
    categories: ["market", "plaza"],
    tone: "lively and invigorating — emphasize open streets, everyday " \
          "urban energy, and a longer, more active wander"
  },
  cozy_corners: {
    label: "Cozy Corners",
    icon: "fa-solid fa-mug-hot",
    categories: ["coffee_shop", "bakery", "bookstore"],
    tone: "warm and unhurried — emphasize small, sheltered stops, quiet " \
          "browsing, and the low hum of a place that isn't asking " \
          "anything of you"
  },
  quiet_history: {
    label: "Quiet History",
    icon: "fa-solid fa-landmark",
    categories: ["historic_site", "monument", "art_gallery"],
    tone: "still and unhurried — emphasize old stone, worn paths, and " \
          "things that have stood a long time without needing anything " \
          "from anyone who passes"
  }
}.freeze
