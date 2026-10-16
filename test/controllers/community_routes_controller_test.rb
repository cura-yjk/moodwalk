require "test_helper"

class CommunityRoutesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:walker) }

  test "requires authentication" do
    sign_out users(:walker)
    get community_routes_path

    assert_redirected_to new_user_session_path
  end

  # The index renders a location label per card. This used to reverse-geocode
  # lazily on read, so a list of cards meant one blocking Mapbox call each --
  # with no WebMock stub registered here, any such call fails this test.
  test "index renders without reaching for the geocoder" do
    get community_routes_path

    assert_response :success
  end

  # :unmeasured is unthemed, so it's a community route by default -- and it
  # has no distance or duration, which exercises the nil-tolerant card helpers.
  test "show renders a community journey that has no distance or duration" do
    get community_route_path(journeys(:unmeasured))

    assert_response :success
  end

  # The cards used to show hand-copied Google photo URLs, some of which had
  # started returning 403, so a card could show a broken image. Now a route
  # nobody has photographed shows one of the app's own bundled photos.
  test "a route nobody has photographed shows a bundled photo on its card" do
    get community_routes_path

    assert_select ".route-card-image[src*=?]", "/assets/cards/"
  end

  # "Other moments from walkers" used to fill up with stock photos of other
  # places when no walker had shared one of this route.
  test "show has no walkers' moments when no walker has shared a photo" do
    get community_route_path(journeys(:unmeasured))

    assert_select ".photo-carousel", count: 0
  end

  test "show refuses a themed journey that nobody has shared a walk on" do
    get community_route_path(journeys(:meguro_loop))

    assert_response :not_found
  end
end
