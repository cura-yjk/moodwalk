require "test_helper"

class ShortlistRouterTest < ActiveSupport::TestCase
  FakeJourney = Struct.new(:estimated_duration_seconds, :overlap_ratio)
  REJECTION = "route backtracks on itself (dead end / u-turn)".freeze
  TARGET = 2000 # seconds

  test "stops at the first route that is the right length and doesn't re-walk itself" do
    routed = route([2000, 0.02], [2000, 0.0])

    assert_equal 1, routed[:calls].size
    assert_equal :option_0, routed[:result].waypoints
  end

  test "routes the next option when a route re-walks too much" do
    routed = route([2000, 0.3], [2000, 0.05])

    assert_equal :option_1, routed[:result].waypoints
  end

  test "routes the next option when a route is the wrong length" do
    routed = route([3000, 0.0], [2100, 0.05])

    assert_equal :option_1, routed[:result].waypoints
  end

  # The time on screen is Mapbox's estimate, which allows for crossings and
  # turns - a route on target by distance still read 20-35% long in minutes.
  test "judges length by the time Mapbox estimates, which is the time shown" do
    routed = route([2600, 0.0], [2050, 0.0])

    assert_equal :option_1, routed[:result].waypoints
  end

  test "reports whether its choice passed, so a caller can compare it with another" do
    passed = route([2000, 0.0])[:result]
    retraced = route([2000, 0.3], [2000, 0.3], [2000, 0.3])[:result]

    assert passed.acceptable
    assert_not retraced.acceptable
    assert_equal(-1, passed.rank <=> retraced.rank)
  end

  # The complaint was walks that ignored the time picked - so when nothing
  # passes both checks, the right length wins over less retracing.
  test "when nothing passes, prefers the right length over less re-walking" do
    routed = route([3000, 0.0], [2000, 0.3], [1000, 0.0])

    assert_equal :option_1, routed[:result].waypoints
  end

  test "when nothing passes, prefers the least re-walked of the right length" do
    routed = route([2000, 0.3], [2000, 0.2], [2000, 0.25])

    assert_equal :option_1, routed[:result].waypoints
  end

  # Measured from a real doorstep: every option came back too long, and the
  # router kept a 1.87x route over a 1.73x one because it re-walked 0% rather
  # than 3% - both well under the limit.
  test "when nothing is the right length, prefers the closest length that isn't retraced" do
    routed = route([3000, 0.0], [2700, 0.03], [1400, 0.3])

    assert_equal :option_1, routed[:result].waypoints
  end

  test "never asks Mapbox more than MAX_ROUTINGS times" do
    routed = route(*Array.new(ShortlistRouter::MAX_ROUTINGS + 2) { [9000, 0.5] })

    assert_equal ShortlistRouter::MAX_ROUTINGS, routed[:calls].size
  end

  test "with no target, any length is the right length" do
    routed = route([9000, 0.02], target: nil)

    assert_equal 1, routed[:calls].size
    assert routed[:result].success?
  end

  test "routes the next option when Mapbox rejects a route" do
    routed = route(:rejected, [2000, 0.05])

    assert_equal :option_1, routed[:result].waypoints
  end

  test "a rejection after a success doesn't lose the success" do
    routed = route([2000, 0.3], :rejected, :rejected)

    assert routed[:result].success?
    assert_equal :option_0, routed[:result].waypoints
  end

  test "fails with Mapbox's reason when every option is rejected" do
    routed = route(:rejected, :rejected, :rejected)

    assert_not routed[:result].success?
    assert_equal REJECTION, routed[:result].error
  end

  private

  # One option per outcome given: a [seconds, overlap] pair for the journey
  # Mapbox routes it to, or :rejected for a route Mapbox turns down.
  def route(*outcomes, target: TARGET)
    options = outcomes.each_index.map { |i| :"option_#{i}" }
    calls = []

    result = ShortlistRouter.new(options, target_seconds: target, tolerance: 0.25) do |option|
      calls << option
      outcome = outcomes[options.index(option)]
      next JourneyGenerator::Result.new(success?: false, error: REJECTION) if outcome == :rejected

      JourneyGenerator::Result.new(success?: true, journey: FakeJourney.new(*outcome))
    end.call

    { result: result, calls: calls }
  end
end
