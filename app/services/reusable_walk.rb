# A saved walk that answers the same request as one that couldn't be built:
# same theme, within RouteBuilder's tolerance of the time picked, starting
# within a few minutes' walk, and not retracing its own streets (see
# ShortlistRouter). Any saved walk counts, not only curated ones.
#
# Used as JourneysController's fallback, and by ThemeSuggestions as the free
# proof that another theme has a walk here.
module ReusableWalk
  module_function

  # About a four-minute walk: a saved walk starting further off isn't the
  # walk that was asked for, it's a trip to somewhere else first.
  START_WITHIN_METERS = 300

  # Nil when there's none.
  def find(lat, lng, theme_key:, duration_minutes: nil)
    candidates = Journey.near(lat, lng, START_WITHIN_METERS).where(theme_key: theme_key.to_s)
    candidates = candidates.where(estimated_duration_seconds: seconds_for(duration_minutes)) if duration_minutes

    candidates.limit(20).find { |journey| journey.overlap_ratio <= ShortlistRouter::MAX_OVERLAP_RATIO }
  end

  def seconds_for(minutes)
    tolerance = RouteBuilder::TOLERANCE_RATIO
    ((minutes * 60 * (1 - tolerance)).round)..((minutes * 60 * (1 + tolerance)).round)
  end
end
