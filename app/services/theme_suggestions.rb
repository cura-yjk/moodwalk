# Which other themes are worth suggesting from here, when the one picked
# can't make a walk - checked, not guessed.
#
# A theme is named if it has a saved walk ready nearby (ReusableWalk:
# free, and a walk certainly exists) or, failing that, enough places within
# reach of a walk this long to build one from (PoiFinder#enough_nearby?: one
# grouped Google request per theme, where building a route asks once per
# category). The second makes a route likely, not certain - it can still come
# out the wrong length - but it's a claim about this spot, where a fixed
# "Calm usually has places" was a claim about Tokyo in general.
#
# Themes are tried busiest first, as measured across three areas, and the
# search stops at LIMIT, so a banner costs at most a few Google calls.
class ThemeSuggestions
  ORDER = %i[calm cheerful refresh recharge].freeze
  LIMIT = 2

  def initialize(lat:, lng:, duration_minutes:, excluding:)
    @lat = lat
    @lng = lng
    @duration_minutes = duration_minutes
    @excluding = excluding.to_sym
  end

  def call
    (ORDER - [@excluding]).lazy.select { |theme_key| worth_suggesting?(theme_key) }.first(LIMIT)
  end

  private

  def worth_suggesting?(theme_key)
    walk_ready?(theme_key) || enough_places?(theme_key)
  end

  def walk_ready?(theme_key)
    ReusableWalk.find(@lat, @lng, theme_key: theme_key, duration_minutes: @duration_minutes).present?
  end

  def enough_places?(theme_key)
    radius = WalkReach.search_radius(@duration_minutes)
    PoiFinder.new(lat: @lat, lng: @lng, categories: THEMES[theme_key][:categories], radius_meters: radius)
             .enough_nearby?(PoiSelector::MIN_WAYPOINTS)
  end
end
