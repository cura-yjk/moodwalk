# Deterministically picks 2-4 real POIs (out of PoiFinder's candidate pool) to
# use as a themed route's waypoints, in a sensible walking order. This used to
# be an LLM's job (see RouteDescriber, which now only writes the description) -
# but picking a combination whose loop distance approximates a target is a
# geometry problem, not a language one, so it's plain Ruby here instead.
class PoiSelector
  MIN_WAYPOINTS = 2
  MAX_WAYPOINTS = 4
  CANDIDATES_PER_CATEGORY = 3

  # Hard ceiling on the combination search's input size (see candidate_pool).
  # 12 keeps it at 781 combinations - the bound the per-category cap alone used
  # to imply back when themes had at most 4 categories.
  MAX_POOL = 12

  # How many of the best-scoring combinations count as good enough to offer.
  #
  # Scoring is deterministic, so without this the same doorstep, theme and
  # duration produce the same waypoints forever -- a user who does not fancy
  # the walk we suggested and asks again gets the identical one back. Five is
  # enough to have somewhere else to go and few enough that every option is
  # still one the scoring actually liked.
  VARIETY_POOL_SIZE = 5

  # Combinations whose distance-fit differs by less than this fraction of the
  # target are treated as equally good on distance, so diversity can break
  # the tie between them - without this, two combos would need to land at
  # the exact same distance (to the meter) before diversity ever mattered.
  DISTANCE_BAND_RATIO = 0.15

  # spread is the winning combo's bearing_spread (0-180, see below) - exposed
  # so RouteBuilder can decide whether a loop actually makes sense here
  # (spread out) or a one-way trip would suit the real candidates better
  # (clustered in one direction), instead of just coin-flipping the two.
  Result = Struct.new(:success?, :waypoints, :spread, :error, keyword_init: true)

  def initialize(lat:, lng:, pois:, target_distance_meters: nil, round_trip: true, variety_seed: nil)
    @lat = lat.to_f
    @lng = lng.to_f
    @pois = Array(pois)
    @target_distance_meters = target_distance_meters
    @round_trip = round_trip
    @variety_seed = variety_seed
  end

  def call
    return empty_result("No nearby places found") if @pois.empty?

    candidates = evaluate_combinations
    return empty_result("Could not find a suitable set of waypoints") if candidates.empty?

    best = pick(candidates)
    Result.new(success?: true, waypoints: best[:order], spread: best[:spread], error: nil)
  end

  private

  # The best-scoring combination, or -- when the caller offers a seed -- one of
  # the best few.
  #
  # The seed is an index into that shortlist rather than a source of
  # randomness, so a caller counting upward walks the pool one route at a time
  # and never repeats until it has offered every option, and the same seed
  # always reproduces the same walk (which is what makes this testable, and
  # what lets a route be regenerated from what produced it).
  def pick(candidates)
    ranked = candidates.max_by(VARIETY_POOL_SIZE) { |candidate| score(candidate) }
    return ranked.first unless @variety_seed

    ranked[@variety_seed % ranked.size]
  end

  # Cap the pool before the combination search below, which is O(pool^4) and
  # so needs a bound that doesn't move when themes grow. Capping per category
  # alone isn't enough: themes now carry 7-8 categories (see
  # config/initializers/themes.rb), so CANDIDATES_PER_CATEGORY on its own
  # allows a pool of 24, which is 12,926 combinations - roughly a second of
  # pure CPU per attempt, and RouteBuilder retries up to MAX_ATTEMPTS times.
  # MAX_POOL holds that at 781 combinations regardless of category count.
  def candidate_pool
    per_category = @pois.group_by { |poi| poi[:category] }
                        .values
                        .map { |group| group.sort_by { |poi| pool_fitness(poi) }.first(CANDIDATES_PER_CATEGORY) }

    round_robin(per_category).first(MAX_POOL)
  end

  # Take one candidate from each category before taking a second from any, so
  # that a cap which actually bites can't quietly collapse the pool onto a
  # single category and take diversity off the table before scoring begins.
  def round_robin(groups)
    return [] if groups.empty?

    groups.map(&:size).max.times.flat_map { |i| groups.filter_map { |group| group[i] } }
  end

  # How well a candidate suits the distance the user asked for. With a target,
  # that's proximity to the radius a tour of that length wants its waypoints
  # at - the same circle JourneyGenerator plants its synthetic waypoints on -
  # so trimming the pool doesn't bias it toward POIs that are merely close by
  # and leave a long walk with nothing far enough out to reach. With no target
  # there's nothing to aim at, so nearest-first, as before.
  def pool_fitness(poi)
    return poi[:distance_meters] unless @target_distance_meters

    (poi[:distance_meters] - ideal_waypoint_radius_meters).abs
  end

  def ideal_waypoint_radius_meters
    @ideal_waypoint_radius_meters ||=
      @round_trip ? @target_distance_meters / (2 * Math::PI) : @target_distance_meters / 2.0
  end

  def evaluate_combinations
    pool = candidate_pool
    return [] if pool.size < MIN_WAYPOINTS

    max_size = [MAX_WAYPOINTS, pool.size].min

    (MIN_WAYPOINTS..max_size).flat_map { |n| pool.combination(n).to_a }.map { |combo| evaluate_combo(combo) }
  end

  def evaluate_combo(combo)
    order, distance = best_order(combo)

    {
      order: order,
      distance: distance,
      diversity: combo.map { |poi| poi[:category] }.uniq.size,
      spread: @round_trip ? bearing_spread(combo) : 0
    }
  end

  # When there's a target distance to hit, honoring it comes first - a combo
  # touching more categories is nicer, but not if it means ignoring the
  # duration the user actually picked. Distance-fit is grouped into coarse
  # bands (see DISTANCE_BAND_RATIO) rather than compared exactly, so spread
  # and diversity still get to decide between options that are similarly
  # close. With no target to honor, there's nothing distance should
  # override, so spread and diversity lead and compactness is a tiebreaker.
  #
  # Spread ranks above diversity: a loop whose waypoints all sit in the same
  # direction from the start retraces nearly the same streets on the way
  # back (looks like a one-way trip with a small detour in it), regardless
  # of how many different categories it touches - so a well-spread-out loop
  # wins over a merely more-diverse one that clusters in one direction.
  def score(candidate)
    if @target_distance_meters
      [-distance_band(candidate), candidate[:spread], candidate[:diversity], -distance_off(candidate)]
    else
      [candidate[:spread], candidate[:diversity], -candidate[:distance]]
    end
  end

  def distance_off(candidate)
    (candidate[:distance] - @target_distance_meters).abs
  end

  def distance_band(candidate)
    (distance_off(candidate) / (@target_distance_meters * DISTANCE_BAND_RATIO)).round
  end

  # How evenly a combo's waypoints are spread around the compass from the
  # start, as the largest gap between consecutive bearings (sorted, with
  # wraparound) subtracted from a full circle - so two waypoints in the same
  # direction score near 0 (one big empty arc on the other side), while two
  # diametrically opposite waypoints score the maximum, 180. Order-independent,
  # so it's computed once per combo rather than per permutation like tour_distance.
  def bearing_spread(combo)
    return 0 if combo.size < 2

    bearings = combo.map { |poi| bearing_from_start(poi) }.sort
    gaps = bearings.each_cons(2).map { |a, b| b - a }
    gaps << (360 - bearings.last + bearings.first)
    360 - gaps.max
  end

  def bearing_from_start(poi)
    GeoDistance.bearing(@lat, @lng, poi[:lat], poi[:lng])
  end

  # Brute-force the visiting order that minimizes total tour distance. At most
  # 4 waypoints, so at most 24 permutations - cheap enough to just try them all.
  # Returns [order, distance] so the caller doesn't have to re-measure the
  # winner that was just measured here.
  def best_order(combo)
    combo.permutation.map { |order| [order, tour_distance(order)] }.min_by(&:last)
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
