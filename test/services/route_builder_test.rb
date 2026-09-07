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
end
