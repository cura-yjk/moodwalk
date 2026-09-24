require "test_helper"

class ReusableWalkTest < ActiveSupport::TestCase
  # journeys(:meguro_loop): calm, 25 minutes, starting here.
  LAT = 35.68
  LNG = 139.77

  test "finds a saved walk of the same theme and time that starts close by" do
    assert_equal journeys(:meguro_loop), ReusableWalk.find(LAT, LNG, theme_key: :calm, duration_minutes: 20)
  end

  test "any time will do when none was picked" do
    assert_equal journeys(:meguro_loop), ReusableWalk.find(LAT, LNG, theme_key: :calm)
  end

  test "not a walk of another theme" do
    assert_nil ReusableWalk.find(LAT, LNG, theme_key: :recharge, duration_minutes: 20)
  end

  test "not a walk well outside the time picked" do
    assert_nil ReusableWalk.find(LAT, LNG, theme_key: :calm, duration_minutes: 10)
  end

  test "not a walk that starts more than a few minutes away" do
    assert_nil ReusableWalk.find(LAT + 0.004, LNG, theme_key: :calm, duration_minutes: 20) # ~450m north
  end
end
