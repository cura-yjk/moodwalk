require "test_helper"

class WalkTest < ActiveSupport::TestCase
  test "rejects a mood outside the known set" do
    walk = walks(:in_progress_walk)
    walk.mood_after = "Furious"

    assert_not walk.valid?, "an arbitrary mood must not be persistable"
    assert_includes walk.errors[:mood_after], "is not included in the list"
  end

  test "accepts the known moods and a nil mood" do
    walk = walks(:in_progress_walk)

    Walk::MOODS.each do |mood|
      walk.mood_after = mood
      assert walk.valid?, "expected #{mood.inspect} to be a valid mood"
    end

    walk.mood_after = nil
    assert walk.valid?, "mood is optional until the walk is reflected on"
  end

  test "finalize_actual_path! measures the tracked path rather than trusting the client" do
    walk = walks(:in_progress_walk)
    add_track_points(walk)

    # Client claims an implausible 99km; the recorded breadcrumbs say ~1km.
    walk.finalize_actual_path!(fallback_distance_km: 99.0, fallback_steps: 999_999)

    assert walk.completed_at.present?
    assert walk.actual_path.present?
    assert_in_delta 1.0, walk.actual_distance.to_f, 0.2,
                    "expected the GPS-derived distance to win over the client's number"
    assert_operator walk.actual_steps, :<, 10_000
  end

  test "finalize_actual_path! falls back to the client's numbers when nothing was tracked" do
    walk = walks(:in_progress_walk)
    assert_equal 0, walk.walk_track_points.count

    walk.finalize_actual_path!(fallback_distance_km: 3.2, fallback_steps: 4200)

    assert_in_delta 3.2, walk.actual_distance.to_f, 0.001
    assert_equal 4200, walk.actual_steps
  end

  test "finalize_actual_path! falls back to the journey's estimate with no client numbers either" do
    walk = walks(:in_progress_walk)
    walk.finalize_actual_path!

    assert_in_delta 2.0, walk.actual_distance.to_f, 0.001
    assert_equal walk.journey.estimated_steps, walk.actual_steps
  end

  test "lifetime_stats aggregates only completed walks" do
    stats = Walk.lifetime_stats(users(:walker).walks)

    assert_equal 1, stats[:walks_count], "the in-progress walk shouldn't count"
    assert_equal 2, stats[:distance_km]
    assert_equal 1, stats[:hours_outside]
  end

  test "lifetime_stats returns zeroes rather than nil for a user with no completed walks" do
    stats = Walk.lifetime_stats(users(:walker).walks.where(id: walks(:in_progress_walk).id))

    assert_equal({ distance_km: 0, hours_outside: 0, walks_count: 0 }, stats)
  end

  private

  # ~1km of due-north breadcrumbs from the journey's start.
  def add_track_points(walk)
    base_lat = 35.68
    base_lng = 139.77
    5.times do |i|
      walk.walk_track_points.create!(
        latitude: base_lat + (i * 250.0 / 111_320.0),
        longitude: base_lng,
        recorded_at: 10.minutes.ago + (i * 60)
      )
    end
  end
end
