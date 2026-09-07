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

    # near-1 + near-2 is the pair closest to the start (smallest raw distances),
    # with an out-and-back tour of ~683m. Pairing either far waypoint with a
    # near one yields a tour of ~1600m - set the target there so the "closest
    # to start" pair is clearly the wrong answer.
    result = PoiSelector.new(lat: START_LAT, lng: START_LNG, pois: pois, target_distance_meters: 1600).call

    assert result.success?
    selected_ids = result.waypoints.map { |wp| wp[:id] }
    refute_equal ["near-1", "near-2"].sort, selected_ids.sort,
                 "expected a combination whose tour distance matches the target, not the one nearest the start"
    assert(selected_ids.include?("far-north") || selected_ids.include?("far-east"))
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
    # Visiting near-then-far (900m total) is shorter than far-then-near
    # (1500m, since you'd walk past "near" again on the way to "far") when
    # there's no return leg to make the two orders equivalent.
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

  private

  def poi(id:, category:, distance_meters:, bearing:)
    lat, lng = case bearing
               when :north
                 [START_LAT + (distance_meters / METERS_PER_DEGREE_LAT), START_LNG]
               when :east
                 [START_LAT, START_LNG + (distance_meters / METERS_PER_DEGREE_LNG)]
               end

    { id: id, name: id, category: category, lat: lat, lng: lng, distance_meters: distance_meters }
  end
end
