# What the user is told when no walk can be offered. None of it is their
# doing, so JourneysController shows it as a notice, not an alert - and every
# sentence says what's actually true from where they are.
class NoWalkNotice
  # Google or Mapbox couldn't be reached, which says nothing about what's
  # nearby - so no "try a longer walk", which couldn't work either.
  UNAVAILABLE = "We couldn't reach our map services just now. Please try again in a moment.".freeze

  def initialize(theme_key:, duration_minutes:, lat:, lng:)
    @theme_key = theme_key
    @duration_minutes = duration_minutes
    @lat = lat
    @lng = lng
  end

  # Names only themes checked from this spot (see ThemeSuggestions), so the
  # next tap is one that will work.
  def nothing_nearby
    where = @duration_minutes ? "within a #{@duration_minutes}-minute walk from here" : "nearby"
    "No #{THEMES[@theme_key][:spots]} #{where}. #{instead}"
  end

  private

  def instead
    suggested = ThemeSuggestions.new(lat: @lat, lng: @lng, duration_minutes: @duration_minutes,
                                     excluding: @theme_key).call
    return places_within_reach(suggested) if suggested.any?
    return "Nothing else is close by right now either." unless @duration_minutes
    return "Try No rush." if @duration_minutes >= JourneysController::DURATION_CHOICES.max

    "Try a longer walk, or No rush."
  end

  def places_within_reach(theme_keys)
    labels = theme_keys.map { |key| THEMES[key][:label] }.to_sentence
    "#{labels} #{theme_keys.one? ? 'has' : 'have'} places within reach."
  end
end
