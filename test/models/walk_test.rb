require "test_helper"

class WalkTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "walker@example.com", password: "password123", name: "Walker")
    @journey = Journey.create!(
      name: "Test loop",
      encoded_polyline: "u{~vFvyys@fS]", # arbitrary valid polyline
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(-0.1, 51.5),
      distance_meters: 1600,
      estimated_steps: 2100
    )
  end

  def build_walk
    Walk.create!(user: @user, journey: @journey, started_at: 20.minutes.ago)
  end

  test "finalize_actual_path! builds a line + real distance/steps from breadcrumbs" do
    walk = build_walk
    base = 10.minutes.ago
    rows = 5.times.map do |i|
      { walk_id: walk.id, longitude: -0.1 + (i * 0.0003), latitude: 51.5 + (i * 0.0002),
        recorded_at: base + (i * 20), created_at: Time.current, updated_at: Time.current }
    end
    WalkTrackPoint.insert_all(rows)

    walk.finalize_actual_path!
    walk.reload

    assert walk.completed_at.present?
    assert_equal 5, walk.actual_route_coordinates.size
    assert_in_delta(-0.1, walk.actual_route_coordinates.first[0], 0.0001)
    assert walk.actual_distance.positive?
    assert walk.actual_steps.positive?
    # distance derived from the track, not the journey's 1.6km estimate
    assert_operator walk.actual_distance, :<, 1.0
  end

  test "finalize_actual_path! falls back to journey estimates without enough points" do
    walk = build_walk

    walk.finalize_actual_path!
    walk.reload

    assert walk.completed_at.present?
    assert_nil walk.actual_path
    assert_empty walk.actual_route_coordinates
    assert_equal 1.6, walk.actual_distance
    assert_equal 2100, walk.actual_steps
  end
end
