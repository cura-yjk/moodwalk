# What a generated route is called.
#
# Every themed route used to be named after its theme, so a list of them read
# "Calm, Calm, Recharge, Calm" -- four names across the whole app, none of which
# said anything about the walk. This builds a name out of what the route
# actually is, from data already on the record when it is saved: where it
# starts, what it leads with, and whether it comes back.
#
# No model involved, deliberately. A route is named the moment it exists, with
# no call to wait on and nothing to fall back to when a key is out of quota --
# the same reason RouteDescriber.fallback_for and JourneyHighlights exist.
class JourneyTitle
  # The Google place types in config/initializers/themes.rb, as the word each
  # one would go by in a title. Short, concrete, and never the raw slug:
  # "Botanical garden Loop" is not a name anyone would write.
  FEATURE_WORDS = {
    "park" => "Park", "city_park" => "Park", "national_park" => "Park",
    "nature_preserve" => "Reserve", "wildlife_refuge" => "Reserve",
    "woods" => "Woodland", "hiking_area" => "Trail", "campground" => "Campsite",
    "picnic_ground" => "Picnic", "playground" => "Playground",
    "botanical_garden" => "Garden", "garden" => "Garden",
    "lake" => "Lakeside", "beach" => "Seaside", "marina" => "Harbour",
    "scenic_spot" => "Viewpoint", "observation_deck" => "Viewpoint",
    "mountain_peak" => "Hilltop",
    "farmers_market" => "Market", "flea_market" => "Market", "market" => "Market",
    "bakery" => "Bakery", "cafe" => "Café",
    "ice_cream_shop" => "Ice Cream", "dessert_shop" => "Dessert"
  }.freeze

  LOOP = "Loop".freeze
  ONE_WAY = "Walk".freeze
  UNNAMED = "Walk".freeze

  def initialize(location_name:, waypoints:, round_trip:, theme_key: nil)
    @location_name = location_name
    @waypoints = Array(waypoints)
    @round_trip = round_trip
    @theme_key = theme_key
  end

  # "Meguro Garden Loop", "Nakameguro Bakery Walk", "Calm Loop" when there is
  # neither a place nor a recognised feature to go on.
  #
  # Deliberately no duration, though db/seeds.rb appends one to its hand-written
  # names: every card that shows a title already shows the minutes beside it,
  # and a title should not repeat what is sitting next to it.
  def call
    parts = [place, feature, shape].compact

    return parts.join(" ") if parts.size > 1

    [theme_label, shape].compact.join(" ")
  end

  private

  def place
    return nil if @location_name.blank? || @location_name == Journey::FALLBACK_LOCATION_NAME

    @location_name
  end

  # The first waypoint's category: what the walk leads with, and the first thing
  # the walker will actually reach.
  def feature
    @waypoints.filter_map { |waypoint| FEATURE_WORDS[waypoint[:category].to_s] }.first
  end

  def shape
    @round_trip ? LOOP : ONE_WAY
  end

  def theme_label
    THEMES.dig(@theme_key.to_s.to_sym, :label)
  end
end
