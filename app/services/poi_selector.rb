# Deterministically picks 2-4 real POIs (out of PoiFinder's candidate pool) to
# use as a themed route's waypoints, in a sensible walking order. This used to
# be an LLM's job (see RouteDescriber, which now only writes the description) -
# but picking a combination whose loop distance approximates a target is a
# geometry problem, not a language one, so it's plain Ruby here instead.
class PoiSelector
  MIN_WAYPOINTS = 2
  MAX_WAYPOINTS = 4
  CANDIDATES_PER_CATEGORY = 3

  Result = Struct.new(:success?, :waypoints, :error, keyword_init: true)

  def initialize(lat:, lng:, pois:, target_distance_meters: nil)
    @lat = lat.to_f
    @lng = lng.to_f
    @pois = Array(pois)
    @target_distance_meters = target_distance_meters
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

  # Diversity first (a walk touching more distinct categories is more
  # interesting), then how close the tour comes to the target distance - or,
  # with no target, simply how compact/walkable it is.
  def score(candidate)
    distance_score = if @target_distance_meters
                       -(candidate[:distance] - @target_distance_meters).abs
                     else
                       -candidate[:distance]
                     end

    [candidate[:diversity], distance_score]
  end

  # Brute-force the visiting order that minimizes total tour distance. At most
  # 4 waypoints, so at most 24 permutations - cheap enough to just try them all.
  def best_order(combo)
    combo.permutation.min_by { |order| tour_distance(order) }
  end

  def tour_distance(ordered_pois)
    points = [{ lat: @lat, lng: @lng }] + ordered_pois + [{ lat: @lat, lng: @lng }]
    points.each_cons(2).sum { |a, b| GeoDistance.haversine(a[:lat], a[:lng], b[:lat], b[:lng]) }
  end

  def empty_result(error_message)
    Result.new(success?: false, waypoints: [], error: error_message)
  end
end
