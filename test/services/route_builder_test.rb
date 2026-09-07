require "test_helper"

class RouteBuilderTest < ActiveSupport::TestCase
  # pick_best is what actually fixes the bug: a later, worse retry attempt
  # (e.g. a radius rescale that shrinks candidate density below viable)
  # must never overwrite an earlier attempt that succeeded. Tested directly
  # since exercising it through #call would require stubbing PoiFinder,
  # PoiSelector, RouteDescriber, and JourneyGenerator's HTTP/LLM calls all at
  # once for what is really just a small piece of decision logic.
  FakeResult = Struct.new(:success?, :journey, :error, keyword_init: true)
  FakeJourney = Struct.new(:distance_meters)

  setup do
    @builder = RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm, duration_minutes: 30)
  end

  test "keeps an earlier success instead of a later failure" do
    success = FakeResult.new(success?: true, journey: FakeJourney.new(2400))
    failure = FakeResult.new(success?: false, error: "Could not find a suitable set of waypoints")

    assert_equal success, @builder.send(:pick_best, success, failure)
  end

  test "replaces a failure with a later success" do
    failure = FakeResult.new(success?: false, error: "no candidates")
    success = FakeResult.new(success?: true, journey: FakeJourney.new(2400))

    assert_equal success, @builder.send(:pick_best, failure, success)
  end

  test "between two successes, keeps whichever is closer to the target distance" do
    target = @builder.instance_variable_get(:@target_distance)
    closer = FakeResult.new(success?: true, journey: FakeJourney.new(target + 50))
    farther = FakeResult.new(success?: true, journey: FakeJourney.new(target + 5000))

    assert_equal closer, @builder.send(:pick_best, farther, closer)
    assert_equal closer, @builder.send(:pick_best, closer, farther)
  end

  test "with no current best yet, takes whatever the first attempt was" do
    failure = FakeResult.new(success?: false, error: "no candidates")
    assert_equal failure, @builder.send(:pick_best, nil, failure)
  end

  # select_waypoints decides loop vs. one-way from the real candidates (via
  # PoiSelector's actual spread scoring) instead of a coin flip - exercised
  # directly with real POI data rather than mocking PoiSelector, since the
  # whole point is that the decision follows from real spread math.
  test "chooses a loop when real candidates spread out enough" do
    pois = [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "south", category: "park", distance_meters: 450, bearing: :south)
    ]

    selection = @builder.send(:select_waypoints, pois)

    assert selection.success?
    assert @builder.instance_variable_get(:@round_trip)
  end

  test "falls back to one-way when real candidates cluster in one direction" do
    pois = [
      poi(id: "north-near", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "north-far", category: "park", distance_meters: 450, bearing: :north)
    ]

    selection = @builder.send(:select_waypoints, pois)

    assert selection.success?
    assert_not @builder.instance_variable_get(:@round_trip)
  end

  private

  def poi(id:, category:, distance_meters:, bearing:)
    lat = @builder.instance_variable_get(:@lat)
    lng = @builder.instance_variable_get(:@lng)
    meters_per_degree_lat = 111_320.0
    meters_per_degree_lng = 111_320.0 * Math.cos(lat * Math::PI / 180)

    poi_lat, poi_lng = case bearing
                       when :north
                         [lat + (distance_meters / meters_per_degree_lat), lng]
                       when :south
                         [lat - (distance_meters / meters_per_degree_lat), lng]
                       end

    { id: id, name: id, category: category, lat: poi_lat, lng: poi_lng, distance_meters: distance_meters }
  end
end
