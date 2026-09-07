# Deterministically picks 2-4 real POIs (out of PoiFinder's candidate pool) to
# use as a themed route's waypoints, in a sensible walking order. This used to
# be an LLM's job (see RouteDescriber, which now only writes the description) -
# but picking a combination whose loop distance approximates a target is a
# geometry problem, not a language one, so it's plain Ruby here instead.
class PoiSelector
  MIN_WAYPOINTS = 2
  MAX_WAYPOINTS = 4
  CANDIDATES_PER_CATEGORY = 3

  # Combinations whose distance-fit differs by less than this fraction of the
  # target are treated as equally good on distance, so diversity can break
  # the tie between them - without this, two combos would need to land at
  # the exact same distance (to the meter) before diversity ever mattered.
  DISTANCE_BAND_RATIO = 0.15

  Result = Struct.new(:success?, :waypoints, :error, keyword_init: true)

  def initialize(lat:, lng:, pois:, target_distance_meters: nil, round_trip: true)
    @lat = lat.to_f
    @lng = lng.to_f
    @pois = Array(pois)
    @target_distance_meters = target_distance_meters
    @round_trip = round_trip
  end

  def call
    return empty_result("No nearby places found") if @pois.empty?

    candidates = evaluate_combinations
    return empty_result("Could not find a suitable set of waypoints") if candidates.empty?

    best = candidates.max_by { |candidate| score(candidate) }
    Result.new(success?: true, waypoints: best[:order], error: nil)
  end

  private

  # Cap candidates per category so the combination search below stays cheap -
  # with up to 4 theme categories that's at most 12 candidates total.
  def candidate_pool
    @pois.group_by { |poi| poi[:category] }
         .flat_map { |_category, group| group.sort_by { |poi| poi[:distance_meters] }.first(CANDIDATES_PER_CATEGORY) }
  end

  def evaluate_combinations
    pool = candidate_pool
    return [] if pool.size < MIN_WAYPOINTS

    max_size = [MAX_WAYPOINTS, pool.size].min

    (MIN_WAYPOINTS..max_size).flat_map { |n| pool.combination(n).to_a }.map do |combo|
      order = best_order(combo)

      { order: order, distance: tour_distance(order), diversity: combo.map { |poi| poi[:category] }.uniq.size }
    end
  end

  # When there's a target distance to hit, honoring it comes first - a combo
  # touching more categories is nicer, but not if it means ignoring the
  # duration the user actually picked. Distance-fit is grouped into coarse
  # bands (see DISTANCE_BAND_RATIO) rather than compared exactly, so
  # diversity still gets to decide between options that are similarly close.
  # With no target to honor, there's nothing distance should override, so
  # diversity leads and compactness is just a tiebreaker.
  def score(candidate)
    if @target_distance_meters
      [-distance_band(candidate), candidate[:diversity], -distance_off(candidate)]
    else
      [candidate[:diversity], -candidate[:distance]]
    end
  end

  def distance_off(candidate)
    (candidate[:distance] - @target_distance_meters).abs
  end

  def distance_band(candidate)
    (distance_off(candidate) / (@target_distance_meters * DISTANCE_BAND_RATIO)).round
  end

  # Brute-force the visiting order that minimizes total tour distance. At most
  # 4 waypoints, so at most 24 permutations - cheap enough to just try them all.
  def best_order(combo)
    combo.permutation.min_by { |order| tour_distance(order) }
  end

  # For a loop, the order that minimizes distance often visits the farthest
  # point first and a nearer one on the way back - fine when the route
  # actually returns to start, but for a one-way trip that same order means
  # walking most of the way back toward start again before stopping, which
  # looks like the path doubling back on itself. Only close the loop back to
  # start when this route actually is one.
  def tour_distance(ordered_pois)
    points = [{ lat: @lat, lng: @lng }] + ordered_pois
    points += [{ lat: @lat, lng: @lng }] if @round_trip
    points.each_cons(2).sum { |a, b| GeoDistance.haversine(a[:lat], a[:lng], b[:lat], b[:lng]) }
  end

  def empty_result(error_message)
    Result.new(success?: false, waypoints: [], error: error_message)
  end
end
