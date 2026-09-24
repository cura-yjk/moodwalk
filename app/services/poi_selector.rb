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

  # How much longer a walk on real streets is than the straight-line tour
  # between its waypoints. Measured on real Mapbox routes around Meguro at
  # 1.22-1.61, averaging about 1.4. Planning on the straight line alone
  # handed back walks around 40% longer than the time the user picked.
  DETOUR_FACTOR = 1.4

  # A loop is only worth walking if it goes round something (see #roundness,
  # 0-1) - below this, it walks back along the way it came or back through
  # the start. For two waypoints equally far out, 0.3 allows anything between
  # about 15 and 135 degrees apart: narrower retraces the outbound leg, wider
  # passes back by the start between them. Such combinations aren't offered
  # as loops at all: ranked by distance first, one used to beat a round loop
  # further down the shortlist, and no loop got walked.
  MIN_LOOP_ROUNDNESS = 0.3

  # roundness is the winning combo's loop shape (0-1, see #roundness) -
  # exposed so RouteBuilder can decide whether a loop actually makes sense
  # here or a one-way trip would suit the real candidates better, instead of
  # just coin-flipping the two.
  #
  # alternatives are the rest of the shortlist, next best first, as ordered
  # waypoints: what RouteBuilder routes instead when the winner's real route
  # turns out to re-walk its own streets, without asking Google again.
  Result = Struct.new(:success?, :waypoints, :roundness, :alternatives, :error, keyword_init: true)

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
    candidates.select! { |candidate| candidate[:roundness] >= MIN_LOOP_ROUNDNESS } if @round_trip
    return empty_result("Could not find a suitable set of waypoints") if candidates.empty?

    best, *rest = shortlist(candidates)
    Result.new(
      success?: true, waypoints: best[:order], roundness: best[:roundness],
      alternatives: rest.map { |candidate| candidate[:order] }, error: nil
    )
  end

  private

  # The best few combinations: the pick first -- the best-scoring one or,
  # when the caller offers a seed, one of the others -- then the rest best
  # first. The rest are what RouteBuilder routes when the pick fails, so they
  # must not be rotated: a rotation put the single best option last, beyond
  # the routes ShortlistRouter tries.
  #
  # The seed is an index into that shortlist rather than a source of
  # randomness, so a caller counting upward walks the pool one route at a time
  # and never repeats until it has offered every option, and the same seed
  # always reproduces the same walk (which is what makes this testable, and
  # what lets a route be regenerated from what produced it).
  def shortlist(candidates)
    ranked = candidates.max_by(VARIETY_POOL_SIZE) { |candidate| score(candidate) }
    pick = ranked[@variety_seed.to_i % ranked.size]
    [pick, *(ranked - [pick])]
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
    @ideal_waypoint_radius_meters ||= begin
      straight_line = @target_distance_meters / DETOUR_FACTOR
      @round_trip ? straight_line / (2 * Math::PI) : straight_line / 2.0
    end
  end

  def evaluate_combinations
    pool = candidate_pool
    return [] if pool.size < MIN_WAYPOINTS

    max_size = [MAX_WAYPOINTS, pool.size].min

    (MIN_WAYPOINTS..max_size).flat_map { |n| pool.combination(n).to_a }.map { |combo| evaluate_combo(combo) }
  end

  def evaluate_combo(combo)
    order, straight_line = best_order(combo)

    {
      order: order,
      distance: straight_line * DETOUR_FACTOR,
      diversity: combo.map { |poi| poi[:category] }.uniq.size,
      roundness: @round_trip ? roundness(order, straight_line) : 0
    }
  end

  # When there's a target distance to hit, honoring it comes first - a combo
  # touching more categories is nicer, but not if it means ignoring the
  # duration the user actually picked. Distance-fit is grouped into coarse
  # bands (see DISTANCE_BAND_RATIO) rather than compared exactly, so spread
  # and loop shape and diversity still get to decide between options that
  # are similarly close. With no target to honor, there's nothing distance
  # should override, so shape and diversity lead and compactness is a
  # tiebreaker.
  #
  # Shape ranks above diversity: a loop that walks back the way it came is
  # re-walked street for street, regardless of how many different
  # categories it touches.
  def score(candidate)
    if @target_distance_meters
      [-distance_band(candidate), candidate[:roundness], candidate[:diversity], -distance_off(candidate)]
    else
      [candidate[:roundness], candidate[:diversity], -candidate[:distance]]
    end
  end

  def distance_off(candidate)
    (candidate[:distance] - @target_distance_meters).abs
  end

  def distance_band(candidate)
    (distance_off(candidate) / (@target_distance_meters * DISTANCE_BAND_RATIO)).round
  end

  # How much ground a loop actually walks around, as the isoperimetric
  # quotient of the polygon start -> waypoints -> start: 4 * pi * area /
  # perimeter^2. 1.0 is a circle, about 0.6 an equilateral triangle, and 0
  # any shape that encloses nothing - which is exactly what a loop that walks
  # back the way it came looks like.
  #
  # This replaced bearing spread, which only asked whether the waypoints sat
  # in different directions from the start. That rewarded two waypoints on
  # opposite sides of it most of all, and the route between them runs back
  # through the start: out, back, out again and back, measured at up to 40%
  # of a route re-walked. Roundness scores that shape 0, and still scores the
  # out-and-back that spread was there to prevent 0 too.
  #
  # Measured on the visiting order, not the bare combo, because the order is
  # what the walker follows; best_order has already chosen it.
  def roundness(order, perimeter)
    return 0 if perimeter.zero?

    points = [[0.0, 0.0]] + order.map { |poi| GeoDistance.local_offset(@lat, @lng, poi[:lat], poi[:lng]) }
    doubled_area = points.zip(points.rotate).sum { |(x1, y1), (x2, y2)| (x1 * y2) - (x2 * y1) }

    4 * Math::PI * (doubled_area.abs / 2) / (perimeter**2)
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
