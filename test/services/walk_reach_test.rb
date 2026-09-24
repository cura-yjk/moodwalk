require "test_helper"

class WalkReachTest < ActiveSupport::TestCase
  test "a walk's target distance is its minutes at the app's walking pace" do
    assert_in_delta 20 * Walk.walking_meters_per_minute, WalkReach.target_distance(20)
    assert_nil WalkReach.target_distance(nil)
  end

  test "searches as far as a one-way walk that long can reach in a straight line" do
    assert_in_delta WalkReach.target_distance(20) / PoiSelector::DETOUR_FACTOR, WalkReach.search_radius(20)
  end

  test "with no duration, searches PoiFinder's default distance" do
    assert_equal PoiFinder::DEFAULT_RADIUS_METERS, WalkReach.search_radius(nil)
  end
end
