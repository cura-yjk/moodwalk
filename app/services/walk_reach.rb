# How far a walk of a given length reaches - shared by RouteBuilder, which
# searches for places that far out, and ThemeSuggestions, which checks other
# themes at exactly the same reach so it never names one a real build
# wouldn't find.
module WalkReach
  module_function

  # The distance a walk of this many minutes covers, at the pace Walk owns.
  # Nil for "No rush".
  def target_distance(duration_minutes)
    duration_minutes.to_f * Walk.walking_meters_per_minute if duration_minutes.present?
  end

  # As far as a one-way walk of that length could end, in a straight line -
  # or, with no duration, PoiFinder's default. It used to stop at half the
  # target, a loop's reach, which left a 10-minute walk only parks 200-330m
  # away, and a two-stop route between those was far too long.
  def search_radius(duration_minutes)
    target = target_distance(duration_minutes)
    target ? target / PoiSelector::DETOUR_FACTOR : PoiFinder::DEFAULT_RADIUS_METERS
  end
end
