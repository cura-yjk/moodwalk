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

  private

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
