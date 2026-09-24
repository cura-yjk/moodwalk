require "test_helper"

# The great-circle math every route in the app is measured with: PoiFinder's
# "how far is this place", PoiSelector's tour-distance scoring, the synthetic
# waypoint ring in JourneyGenerator, and Journey#turn_waypoints' turn direction.
#
# Expected values here are derived from the sphere's own geometry -- a degree of
# arc is 1/360th of the circumference -- rather than recorded from a previous
# run, so a wrong formula fails instead of being enshrined.
class GeoDistanceTest < ActiveSupport::TestCase
  # Written out rather than read from GeoDistance::EARTH_RADIUS_METERS: an
  # expectation derived from the constant it is checking moves whenever the
  # constant does, and every assertion below passes just as happily on the
  # 6_371_000 mean radius, which would quietly resize every route in the app.
  WGS84_EQUATORIAL_RADIUS = 6_378_137.0
  DEGREE_METERS = (2 * Math::PI * WGS84_EQUATORIAL_RADIUS) / 360
  QUARTER_CIRCUMFERENCE = (Math::PI * WGS84_EQUATORIAL_RADIUS) / 2

  test "measures against the WGS84 equatorial radius, the one Mapbox reports distances on" do
    assert_in_delta WGS84_EQUATORIAL_RADIUS, GeoDistance::EARTH_RADIUS_METERS, 1e-9
  end

  # --- haversine ---------------------------------------------------------

  test "a degree of arc measures one three-hundred-sixtieth of the circumference" do
    assert_in_delta DEGREE_METERS, GeoDistance.haversine(0, 0, 0, 1), 0.001
    assert_in_delta DEGREE_METERS, GeoDistance.haversine(0, 0, 1, 0), 0.001
  end

  test "a degree of latitude measures the same on every meridian and at every latitude" do
    at_equator = GeoDistance.haversine(0, 0, 1, 0)
    up_north = GeoDistance.haversine(50, 20, 51, 20)

    assert_in_delta at_equator, up_north, 0.001
  end

  test "a degree of longitude shrinks with the cosine of the latitude" do
    # Not exactly half: the great circle between two points on the 60th
    # parallel cuts slightly poleward of the parallel itself. A tenth of a
    # percent is plenty to catch a missing cos() term, which would leave this
    # equal to a full degree.
    at_sixty = GeoDistance.haversine(60, 0, 60, 1)

    assert_in_delta DEGREE_METERS * Math.cos(60 * Math::PI / 180), at_sixty, DEGREE_METERS * 0.001
  end

  test "a point is no distance from itself" do
    assert_in_delta 0, GeoDistance.haversine(35.68, 139.77, 35.68, 139.77), 1e-9
  end

  test "distance does not depend on which point you start from" do
    there = GeoDistance.haversine(35.68, 139.77, 34.69, 135.50)
    back = GeoDistance.haversine(34.69, 135.50, 35.68, 139.77)

    assert_in_delta there, back, 1e-9
  end

  test "antipodal points are half a circumference apart" do
    assert_in_delta Math::PI * WGS84_EQUATORIAL_RADIUS, GeoDistance.haversine(0, 0, 0, 180), 0.001
  end

  test "crossing the antimeridian is measured the short way round" do
    # 1 degree apart, on opposite sides of 180. Subtracting the longitudes
    # naively gives 359 degrees and a distance 359x too large.
    assert_in_delta DEGREE_METERS, GeoDistance.haversine(0, 179.5, 0, -179.5), 0.001
  end

  # --- bearing -----------------------------------------------------------

  test "the cardinal directions come back as compass degrees" do
    assert_in_delta 0, GeoDistance.bearing(0, 0, 1, 0), 1e-9
    assert_in_delta 90, GeoDistance.bearing(0, 0, 0, 1), 1e-9
    assert_in_delta 180, GeoDistance.bearing(0, 0, -1, 0), 1e-9
    assert_in_delta 270, GeoDistance.bearing(0, 0, 0, -1), 1e-9
  end

  test "bearings are normalized into 0...360 rather than going negative" do
    # atan2 returns -90 for due west; PoiSelector's spread arithmetic assumes
    # a compass value, and a negative one silently widens every arc it measures.
    westerly = GeoDistance.bearing(35.68, 139.77, 35.68, 139.00)

    assert_operator westerly, :>=, 0
    assert_operator westerly, :<, 360
    assert_in_delta 270, westerly, 0.5
  end

  test "reversing a short leg turns the bearing around by half the compass" do
    there = GeoDistance.bearing(35.68, 139.77, 35.69, 139.78)
    back = GeoDistance.bearing(35.69, 139.78, 35.68, 139.77)

    assert_in_delta 180, (there - back).abs, 0.01
  end

  # --- destination_point -------------------------------------------------

  test "travelling a degree east of the origin lands on the first meridian" do
    point = GeoDistance.destination_point(0, 0, DEGREE_METERS, 90)

    assert_in_delta 0, point[:lat], 1e-9
    assert_in_delta 1, point[:lng], 1e-9
  end

  test "travelling a quarter circumference north from the equator reaches the pole" do
    point = GeoDistance.destination_point(0, 0, QUARTER_CIRCUMFERENCE, 0)

    assert_in_delta 90, point[:lat], 1e-6
  end

  test "destination_point and haversine agree in both directions, on every bearing" do
    # JourneyGenerator plants its synthetic ring with destination_point and then
    # measures the resulting route with haversine. If the two disagree, the ring
    # is not the radius it asked for and the retry loop chases a moving target.
    (0...360).step(15) do |bearing|
      point = GeoDistance.destination_point(35.68, 139.77, 1_500, bearing)

      assert_in_delta 1_500, GeoDistance.haversine(35.68, 139.77, point[:lat], point[:lng]), 0.001,
                      "distance disagreed on bearing #{bearing}"
      assert_in_delta bearing, GeoDistance.bearing(35.68, 139.77, point[:lat], point[:lng]), 0.001,
                      "bearing disagreed on bearing #{bearing}"
    end
  end

  test "going nowhere leaves you where you started" do
    point = GeoDistance.destination_point(35.68, 139.77, 0, 42)

    assert_in_delta 35.68, point[:lat], 1e-9
    assert_in_delta 139.77, point[:lng], 1e-9
  end

  test "local_offset puts a point in metres east and north of the origin" do
    north = GeoDistance.destination_point(35.63, 139.70, 500, 0)
    east = GeoDistance.destination_point(35.63, 139.70, 500, 90)

    north_east, north_north = GeoDistance.local_offset(35.63, 139.70, north[:lat], north[:lng])
    east_east, east_north = GeoDistance.local_offset(35.63, 139.70, east[:lat], east[:lng])

    assert_in_delta 0, north_east, 1
    assert_in_delta 500, north_north, 1
    assert_in_delta 500, east_east, 1
    assert_in_delta 0, east_north, 1
  end
end
