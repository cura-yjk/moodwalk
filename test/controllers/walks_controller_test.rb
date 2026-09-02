require "test_helper"

class WalksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "walker@example.com", password: "password123", name: "Walker")
    @journey = Journey.create!(
      name: "Test loop",
      encoded_polyline: "u{~vFvyys@fS]",
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(-0.1, 51.5),
      distance_meters: 1600,
      estimated_steps: 2100
    )
    @walk = Walk.create!(user: @user, journey: @journey, started_at: 5.minutes.ago)
  end

  test "track persists a batch of breadcrumbs for the current user's walk" do
    sign_in @user

    assert_difference -> { @walk.walk_track_points.count }, 2 do
      post track_walk_path(@walk), params: {
        points: [
          { latitude: 51.5001, longitude: -0.1001, accuracy_meters: 8, recorded_at: "2026-09-02T10:00:00Z" },
          { latitude: 51.5002, longitude: -0.1002, accuracy_meters: 12, recorded_at: "2026-09-02T10:00:05Z" }
        ]
      }, as: :json
    end

    assert_response :no_content
  end

  test "track skips entries missing coordinates" do
    sign_in @user

    assert_difference -> { @walk.walk_track_points.count }, 1 do
      post track_walk_path(@walk), params: {
        points: [
          { latitude: 51.5001, longitude: -0.1001, recorded_at: "2026-09-02T10:00:00Z" },
          { latitude: nil, longitude: nil, recorded_at: "2026-09-02T10:00:05Z" }
        ]
      }, as: :json
    end
  end

  test "track won't write to another user's walk" do
    other = User.create!(email: "intruder@example.com", password: "password123", name: "Nope")
    sign_in other

    post track_walk_path(@walk), params: { points: [{ latitude: 51.5, longitude: -0.1, recorded_at: "2026-09-02T10:00:00Z" }] }, as: :json

    assert_response :not_found
    assert_equal 0, @walk.walk_track_points.count
  end

  test "track requires authentication" do
    post track_walk_path(@walk), params: { points: [] }, as: :json
    assert_response :unauthorized
  end
end
