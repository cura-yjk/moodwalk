require "test_helper"

class JourneyGeneratorTest < ActiveSupport::TestCase
  START_LAT = 35.68
  START_LNG = 139.77
  WAYPOINT = { lat: 35.685, lng: 139.775 }.freeze
  FAR_FROM_ANYTHING = { lat: 35.72, lng: 139.83 }.freeze # nowhere near the start or the waypoint

  setup do
    stub_reverse_geocode
  end

  test "succeeds when the route's only u-turn is at the real waypoint" do
    stub_directions(legs: [
                      leg_with_steps([step(modifier: "left", location: [WAYPOINT[:lng], WAYPOINT[:lat]])]),
                      leg_with_steps([step(modifier: "uturn", location: [WAYPOINT[:lng], WAYPOINT[:lat]])])
                    ])

    result = build_generator.call

    assert result.success?, result.error
  end

  test "fails when a u-turn happens away from every waypoint" do
    stub_directions(legs: [
                      leg_with_steps([step(modifier: "left", location: [WAYPOINT[:lng], WAYPOINT[:lat]])]),
                      leg_with_steps([step(modifier: "uturn",
                                           location: [
                                             FAR_FROM_ANYTHING[:lng], FAR_FROM_ANYTHING[:lat]
                                           ])])
                    ])

    result = build_generator.call

    assert_not result.success?
    assert_match(/dead end/, result.error)
  end

  test "does not apply the dead-end check to non-themed synthetic-loop routes" do
    # No theme_key -> the dead-end check should never even look at these legs,
    # even though this one contains a u-turn nowhere near the start.
    far_uturn = step(modifier: "uturn", location: [FAR_FROM_ANYTHING[:lng], FAR_FROM_ANYTHING[:lat]])
    stub_directions(distance: 1000.0, legs: [leg_with_steps([far_uturn])])

    generator = JourneyGenerator.new(lat: START_LAT, lng: START_LNG, target_distance_meters: 1000.0, round_trip: true)
    result = generator.call

    assert result.success?, result.error
  end

  # The duration shown on a route's card is Mapbox's estimate, and Mapbox
  # estimates at its own default pace unless told otherwise -- which is not the
  # pace RouteBuilder sized the route for. A route planned to take thirty
  # minutes came back describing itself as twenty-eight.
  test "asks Mapbox to estimate at the pace the route was planned for" do
    stub_directions(legs: [{ "steps" => [] }], distance: 2_400.0, duration: 1_800.0)

    JourneyGenerator.new(lat: 35.68, lng: 139.77, target_distance_meters: 2_400, round_trip: true).call

    assert_requested :get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/} do |request|
      request.uri.query_values["walking_speed"].to_f == Walk::WALKING_METERS_PER_SECOND
    end
  end

  test "the pace that sizes a route is the pace that measures it" do
    # One constant, two users: RouteBuilder multiplies minutes by it to get a
    # target distance, and Mapbox divides a distance by it to get minutes back.
    # If they ever drift, every duration in the app is quietly wrong.
    minutes = 30
    target = minutes * RouteBuilder::WALKING_METERS_PER_MINUTE

    assert_in_delta minutes * 60, target / Walk::WALKING_METERS_PER_SECOND, 0.001
  end


  def build_generator
    JourneyGenerator.new(
      lat: START_LAT,
      lng: START_LNG,
      waypoints: [WAYPOINT],
      description: "A quiet loop.",
      theme_key: :calm,
      name: "Calm",
      round_trip: true
    )
  end

  def step(modifier:, location:)
    { "maneuver" => { "modifier" => modifier, "location" => location } }
  end

  def leg_with_steps(steps)
    { "steps" => steps }
  end

  def stub_reverse_geocode
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, body: { "features" => [] }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_directions(legs:, distance: 1000.0, duration: 600.0)
    body = {
      "code" => "Ok",
      "routes" => [
        { "distance" => distance, "duration" => duration, "geometry" => "encodedpolyline", "legs" => legs }
      ]
    }

    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/})
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end
