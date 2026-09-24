require "test_helper"

class PoiSelectorTest < ActiveSupport::TestCase
  # Le Wagon Meguro, roughly - exact coordinates don't matter, only the
  # relative offsets used to build POIs below.
  START_LAT = 35.68
  START_LNG = 139.77

  METERS_PER_DEGREE_LAT = 111_320.0
  METERS_PER_DEGREE_LNG = 111_320.0 * Math.cos(START_LAT * Math::PI / 180)

  test "picks a diverse combination across categories when candidates allow it" do
    pois = [
      poi(id: "park-1", category: "park", distance_meters: 200, bearing: :north),
      poi(id: "park-2", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "bakery-1", category: "bakery", distance_meters: 250, bearing: :east)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois).call

    assert result.success?
    categories = result.waypoints.map { |wp| wp[:category] }
    assert_equal 2, categories.uniq.size, "expected the winning combination to span both categories"
  end

  test "with a target distance, prefers the combination closest to that distance over the one nearest the start" do
    close_pair = [
      poi(id: "near-1", category: "park", distance_meters: 200, bearing: :north),
      poi(id: "near-2", category: "park", distance_meters: 200, bearing: :east)
    ]
    far_options = [
      poi(id: "far-north", category: "park", distance_meters: 800, bearing: :north),
      poi(id: "far-east", category: "park", distance_meters: 800, bearing: :east)
    ]
    pois = close_pair + far_options

    # near-1+near-2 is closest to the start (~683m tour); pairing either far
    # waypoint with a near one yields ~1600m in straight lines, ~2240m once
    # walked (see DETOUR_FACTOR) - target that to make "closest to start" the
    # wrong answer.
    target = 1600 * PoiSelector::DETOUR_FACTOR
    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: target).call

    assert result.success?
    selected_ids = result.waypoints.map { |wp| wp[:id] }
    refute_equal ["near-1", "near-2"].sort, selected_ids.sort,
                 "expected a combination whose tour distance matches the target, not the one nearest the start"
    assert(selected_ids.include?("far-north") || selected_ids.include?("far-east"))
  end

  # Streets are never straight lines: measured on real routes, the walk came
  # out 1.2-1.6 times the straight-line tour. Planning on the straight line
  # handed back walks about 40% longer than the time the user picked.
  test "plans on the distance actually walked, not the straight line" do
    pois = [
      poi(id: "north-mid", category: "park", distance_meters: 300, bearing: :north),
      poi(id: "east-mid", category: "park", distance_meters: 300, bearing: :east),
      poi(id: "north-far", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "east-far", category: "park", distance_meters: 400, bearing: :east)
    ]

    # The far pair's straight-line loop is ~1366m, right on target; the mid
    # pair's is ~1024m, which is ~1434m once walked on real streets.
    result = PoiSelector.new(
      lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: 1400, round_trip: true
    ).call

    assert_equal %w[east-mid north-mid], result.waypoints.map { |wp| wp[:id] }.sort
  end

  test "prefers hitting the target distance over touching more categories" do
    # A same-category pair that lands almost exactly on the target...
    close_same_category = [
      poi(id: "park-near", category: "park", distance_meters: 300, bearing: :north),
      poi(id: "park-far", category: "park", distance_meters: 300, bearing: :east)
    ]
    # ...vs. a two-category pair that's diverse but far off target. Diversity
    # alone shouldn't win when it means badly missing the duration the user
    # actually asked for.
    diverse_but_far = [
      poi(id: "bakery-far", category: "bakery", distance_meters: 2000, bearing: :north)
    ]
    pois = close_same_category + diverse_but_far

    result = PoiSelector.new(
      lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: 1000, round_trip: true
    ).call

    assert result.success?
    selected_ids = result.waypoints.map { |wp| wp[:id] }.sort
    assert_equal ["park-far", "park-near"], selected_ids
  end

  # Same category throughout (diversity ties at 1 everywhere) and only 3
  # candidates (under CANDIDATES_PER_CATEGORY's cap of 3) - isolating loop
  # shape and distance as the only factors deciding between them.
  test "for a loop, prefers going round the start over an out-and-back" do
    pois = [
      poi(id: "north-near", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "north-far", category: "park", distance_meters: 450, bearing: :north),
      poi(id: "east", category: "park", distance_meters: 450, bearing: :east)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, round_trip: true).call

    assert result.success?
    selected_ids = result.waypoints.map { |wp| wp[:id] }.sort
    assert_not_equal ["north-far", "north-near"], selected_ids,
                     "two waypoints due north of the start make a loop that walks back the way it came"
  end

  # Measured on real routes: a loop through waypoints on opposite sides of the
  # start walks out to one, back through the start, out to the other and back
  # again - a cloverleaf, the most re-walked shape of all. Bearing spread used
  # to score this pair highest of any.
  test "for a loop, does not pair waypoints on opposite sides of the start" do
    pois = [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "south", category: "park", distance_meters: 450, bearing: :south),
      poi(id: "east", category: "park", distance_meters: 420, bearing: :east)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, round_trip: true).call

    assert result.success?
    assert_includes result.waypoints.map { |wp| wp[:id] }, "east",
                    "north + south alone passes back through the start between them"
  end

  test "a loop that doubles back through the start isn't offered as a loop" do
    pois = [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "south", category: "park", distance_meters: 400, bearing: :south)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, round_trip: true).call

    assert_not result.success?, "north + south walks out, back through the start, and out again"
  end

  test "a loop that goes round the start scores its roundness" do
    pois = [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "east", category: "park", distance_meters: 400, bearing: :east)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, round_trip: true).call

    # A right isosceles triangle: 4 * pi * (400^2 / 2) / (800 + 400 * sqrt(2))^2.
    assert_in_delta 0.539, result.roundness, 0.01
  end

  test "loop shape doesn't matter for a one-way trip - picks the more compact option" do
    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: clustered_and_spread_pois, round_trip: false).call

    assert result.success?
    selected_ids = result.waypoints.map { |wp| wp[:id] }.sort
    assert_equal ["north-far", "north-near"], selected_ids,
                 "with no return leg, loop shape isn't meaningful - the shorter option should win"
  end

  test "falls back to a valid combination when only one category has candidates" do
    pois = [
      poi(id: "park-1", category: "park", distance_meters: 200, bearing: :north),
      poi(id: "park-2", category: "park", distance_meters: 400, bearing: :east),
      poi(id: "park-3", category: "park", distance_meters: 600, bearing: :north)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois).call

    assert result.success?
    assert_includes PoiSelector::MIN_WAYPOINTS..PoiSelector::MAX_WAYPOINTS, result.waypoints.size
  end

  test "for a one-way trip, orders waypoints outward instead of there-and-partway-back" do
    pois = [
      poi(id: "near", category: "park", distance_meters: 300, bearing: :north),
      poi(id: "far", category: "park", distance_meters: 900, bearing: :north)
    ]

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, round_trip: false).call

    assert result.success?
    # near-then-far (900m) beats far-then-near (1500m, walking past "near"
    # twice) once there's no return leg to make the two orders equivalent.
    assert_equal(["near", "far"], result.waypoints.map { |wp| wp[:id] })
  end

  test "fails when fewer than two candidates exist" do
    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: []).call
    assert_not result.success?
    assert_equal "No nearby places found", result.error

    single = [poi(id: "park-1", category: "park", distance_meters: 200, bearing: :north)]
    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: single).call
    assert_not result.success?
    assert_equal "Could not find a suitable set of waypoints", result.error
  end

  # Regression test for the MAX_POOL cap. With 8 categories the raw pool is 24
  # candidates, well over MAX_POOL, so the cap actually bites here. Trimming it
  # nearest-first would keep only the close POIs and make a long walk
  # unreachable - the pool has to stay biased toward the distance asked for.
  test "with a long target, the pool cap keeps far candidates rather than the nearest ones" do
    pois = 8.times.flat_map do |i|
      category = "category-#{i}"
      [
        poi(id: "#{category}-near", category: category, distance_meters: 150, bearing: :north),
        poi(id: "#{category}-near-2", category: category, distance_meters: 200, bearing: :east),
        # Round the compass, so a long loop through far places can go round
        # the start rather than back through it.
        poi(id: "#{category}-far", category: category, distance_meters: 1400, bearing: i * 45)
      ]
    end

    target = 9000
    result = PoiSelector.new(
      lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: target, round_trip: true
    ).call

    assert result.success?
    selected = result.waypoints.map { |wp| wp[:id] }

    # The scorer may still mix in a nearer POI if that lands closer to the
    # target - what must not happen is the cap discarding the far candidates
    # outright, which would leave nothing able to reach 9km.
    assert_operator selected.count { |id| id.end_with?("-far") }, :>=, 2,
                    "expected the cap to retain the far candidates a #{target}m loop needs, got #{selected.inspect}"

    # Deliberately not asserting the tour length here: best_order minimizes it,
    # so a loop through waypoints on the ideal radius still comes in under the
    # target. That tradeoff is the scorer's, and predates this cap.
  end

  test "the pool cap still leaves room for more than one category" do
    pois = 8.times.flat_map do |i|
      category = "category-#{i}"
      3.times.map do |n|
        poi(id: "#{category}-#{n}", category: category, distance_meters: 300 + (n * 50),
            bearing: n.zero? ? :north : :east)
      end
    end

    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois).call

    assert result.success?
    categories = result.waypoints.map { |wp| wp[:category] }.uniq
    assert_operator categories.size, :>, 1,
                    "capping the pool must not collapse it onto a single category"
  end

  # --- variety -----------------------------------------------------------
  #
  # Scoring is deterministic, which is what makes a route reproducible -- and
  # also what made the same doorstep hand back the same walk forever.

  test "with no seed, still returns the single best-scoring combination" do
    pois = spread_pois

    unseeded = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: 1_600).call
    seeded_to_the_top = PoiSelector.new(
      lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: 1_600, variety_seed: 0
    ).call

    assert_equal ids(seeded_to_the_top), ids(unseeded)
  end

  test "a different seed offers a different walk" do
    walks = (0..3).map { |seed| ids(select_with(seed: seed)) }

    assert_operator walks.uniq.size, :>, 1, "every seed produced the same waypoints: #{walks.first}"
  end

  test "consecutive seeds never repeat within the length of the shortlist" do
    # What a user tapping "not this one" experiences: each tap must offer
    # something they have not just turned down.
    walks = (0...PoiSelector::VARIETY_POOL_SIZE).map { |seed| ids(select_with(seed: seed)) }

    assert_equal walks.size, walks.uniq.size, "a seed repeated an earlier walk: #{walks}"
  end

  test "the same seed always reproduces the same walk" do
    assert_equal ids(select_with(seed: 3)), ids(select_with(seed: 3))
  end

  test "seeds wrap around the shortlist instead of falling off the end" do
    # The controller counts upward for the length of a session and never resets,
    # so the seed is routinely larger than the shortlist.
    assert_equal ids(select_with(seed: 1)), ids(select_with(seed: 1 + PoiSelector::VARIETY_POOL_SIZE))
    assert_predicate select_with(seed: 10_001), :success?
  end

  # RouteBuilder routes these when the pick turns out to re-walk its own
  # streets, which only Mapbox's route can show - so no more Google calls.
  test "offers the rest of the shortlist as alternatives, best first" do
    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: spread_pois, target_distance_meters: 1_600).call
    next_best = PoiSelector.new(
      lat: START_LAT, lng: START_LNG, pois: spread_pois, target_distance_meters: 1_600, variety_seed: 1
    ).call

    assert_equal PoiSelector::VARIETY_POOL_SIZE - 1, result.alternatives.size
    assert_not_includes result.alternatives, result.waypoints
    assert_equal ids(next_best), result.alternatives.first.map { |waypoint| waypoint[:id] }
  end

  # The seed is for variety in the pick. The alternatives are what gets
  # routed when the pick fails, so they must be the best of the rest - a
  # rotation put the single best option last, where the router never reached
  # it.
  test "alternatives after a seeded pick are the rest of the shortlist, best first" do
    best_first = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: spread_pois, target_distance_meters: 1_600).call
    seeded = select_with(seed: 2)

    expected = ([best_first.waypoints] + best_first.alternatives) - [seeded.waypoints]
    assert_equal expected, seeded.alternatives
  end

  test "variety never reaches outside the shortlist the scoring approved" do
    shortlist = (0...PoiSelector::VARIETY_POOL_SIZE).map { |seed| ids(select_with(seed: seed)) }
    reached = (0..40).map { |seed| ids(select_with(seed: seed)) }.uniq

    assert_equal [], reached - shortlist, "a seed produced a combination outside the top few"
  end

  private

  def select_with(seed:)
    PoiSelector.new(
      lat: START_LAT, lng: START_LNG, pois: spread_pois, target_distance_meters: 1_600, variety_seed: seed
    ).call
  end

  def ids(result)
    result.waypoints.map { |waypoint| waypoint[:id] }
  end

  # Enough candidates, spread around the compass and across categories, that
  # the scoring has a real shortlist rather than one viable combination.
  def spread_pois
    9.times.map do |i|
      poi(id: "poi-#{i}", category: %w[park garden lake][i % 3],
          distance_meters: 220 + (i * 60), bearing: (i * 41) % 360)
    end
  end


  def clustered_and_spread_pois
    [
      poi(id: "north-near", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "north-far", category: "park", distance_meters: 450, bearing: :north),
      poi(id: "south", category: "park", distance_meters: 450, bearing: :south)
    ]
  end

  # bearing takes either one of the three named directions the tests above read
  # better with, or a compass angle when what matters is being spread around
  # the circle rather than being in a particular direction.
  def poi(id:, category:, distance_meters:, bearing:)
    lat, lng = case bearing
               when :north
                 [START_LAT + (distance_meters / METERS_PER_DEGREE_LAT), START_LNG]
               when :south
                 [START_LAT - (distance_meters / METERS_PER_DEGREE_LAT), START_LNG]
               when :east
                 [START_LAT, START_LNG + (distance_meters / METERS_PER_DEGREE_LNG)]
               when Numeric
                 point = GeoDistance.destination_point(START_LAT, START_LNG, distance_meters, bearing)
                 [point[:lat], point[:lng]]
               end

    { id: id, name: id, category: category, lat: lat, lng: lng, distance_meters: distance_meters }
  end
end
