# The short phrases on a journey's preview, and the words shown as its tags.
#
# Lifted out of Journey with its four lookup tables: it is a body of rules
# about themes and wording, and needs nothing from the record but the theme and
# the text. Journey#highlights and #tags still read the same from outside.
class JourneyHighlights
  def initialize(theme_key:, text:)
    @theme_key = theme_key
    @text = text.to_s
  end

  HIGHLIGHT_PHRASES = {
    "Nature" => { icon: "🌿", text: "Greenery along the way" },
    "Water" => { icon: "💧", text: "Passes near water" },
    "Quiet" => { icon: "🤫", text: "Calm, quiet stretches" },
    "Historic" => { icon: "🏛️", text: "Old streets and landmarks" },
    "Lively" => { icon: "🚶", text: "Passes active areas" },
    "Views" => { icon: "🌅", text: "Opens out to a view" },
    "Walk" => { icon: "☀️", text: "Mostly open streets" }
  }.freeze

  # Google place types (config/initializers/themes.rb) -> the phrases above.
  #
  # Needed because theme_tags renders the raw place-type slug ("Botanical
  # garden"), which never matched HIGHLIGHT_PHRASES' mood words -- so every
  # themed journey silently had zero highlights, and only the LLM-written
  # highlights_text ever showed. Left over from the Mapbox -> Google Places
  # migration, when the slugs changed and this mapping stopped lining up.
  CATEGORY_HIGHLIGHTS = {
    "park" => "Nature", "city_park" => "Nature", "national_park" => "Nature",
    "nature_preserve" => "Nature", "wildlife_refuge" => "Nature", "woods" => "Nature",
    "garden" => "Nature", "botanical_garden" => "Nature", "hiking_area" => "Nature",
    "campground" => "Nature", "picnic_ground" => "Nature",
    "lake" => "Water", "beach" => "Water", "marina" => "Water",
    "scenic_spot" => "Views", "observation_deck" => "Views", "mountain_peak" => "Views",
    "farmers_market" => "Lively", "flea_market" => "Lively", "market" => "Lively",
    "bakery" => "Lively", "cafe" => "Lively", "ice_cream_shop" => "Lively",
    "dessert_shop" => "Lively", "playground" => "Lively"
  }.freeze

  # For a themed journey, what the route passes comes from the theme's real
  # categories; anything the name/description mentions is folded in on top
  # (a generated description saying "quiet" earns the Quiet phrase). Unthemed
  # journeys have only their text to go on, as before.
  def phrases
    highlight_keys.filter_map { |key| HIGHLIGHT_PHRASES[key] }.first(3)
  end

  TEXT_TAG_KEYWORDS = {
    "Nature" => /tree|leaf|leaves|branch|garden|grass|greenery|forest|park/i,
    "Water" => /water|stream|river|lake|pond|shore|waterfront/i,
    "Quiet" => /quiet|hushed|still|calm|silence/i,
    "Historic" => /old|worn|weathered|stone|brick|landmark|monument/i,
    "Lively" => /market|bakery|bright|color|liveliness|delight/i
  }.freeze

  def tags
    return theme_tags if themed?

    text_derived_tags
  end

  private

  def highlight_keys
    (category_highlight_keys + text_tag_matches).uniq.presence || ["Walk"]
  end

  def category_highlight_keys
    return [] unless themed?

    THEMES.dig(@theme_key.to_sym, :categories).to_a.filter_map { |slug| CATEGORY_HIGHLIGHTS[slug] }.uniq
  end

  def themed?
    @theme_key.present? && THEMES.key?(@theme_key.to_sym)
  end

  def theme_tags
    THEMES.dig(@theme_key.to_sym, :categories).to_a.map { |slug| slug.tr("_", " ").capitalize }
  end

  def text_derived_tags
    text_tag_matches.presence || ["Walk"]
  end

  def text_tag_matches
    TEXT_TAG_KEYWORDS.select { |_, pattern| @text.match?(pattern) }.keys
  end
end
