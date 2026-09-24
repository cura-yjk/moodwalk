require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Production answered 406 to a phone on /walks and twice on /, because Rails'
  # generated `allow_browser versions: :modern` demands webp, web push and
  # badges -- none of which this app uses. Someone could not open the app at all.
  test "an older browser is let in rather than turned away" do
    get new_user_session_path, headers: { "HTTP_USER_AGENT" => OLD_SAFARI }

    assert_response :success
  end

  test "an older browser is let into a signed-in page too" do
    sign_in users(:walker)

    get walks_path, headers: { "HTTP_USER_AGENT" => OLD_SAFARI }

    assert_response :success
  end

  # Signed out, the home page used to render an empty screen - everything on
  # it is for a signed-in walker, and nothing said how to become one.
  test "a signed-out visitor is sent to the login form" do
    get root_path

    assert_redirected_to new_user_session_path
  end

  # Devise's own redirect would greet a first visit with "You need to sign in
  # or sign up before continuing." - a warning, for opening the app.
  test "without a warning for having opened the app" do
    get root_path

    assert_nil flash[:alert]
  end

  # --- the suggestion carousel -------------------------------------------

  test "suggests the routes nearest the walker first" do
    sign_in users(:walker) # located in Meguro, next to near_suggestion

    get root_path

    assert_response :success
    assert_equal journeys(:near_suggestion).name, suggested_names.first
  end

  # Ordering by distance, proven by moving the walker rather than by trusting
  # the first test: with only a couple of suggestible routes, "nearest first"
  # and "whatever order the table returns" produce the same list, so dropping
  # Journey.near entirely would otherwise pass.
  test "the nearest route changes when the walker does" do
    walker = users(:walker)
    walker.update!(current_latitude: 35.63, current_longitude: 139.859) # beside far_route
    sign_in walker

    get root_path

    assert_equal journeys(:far_route).name, suggested_names.first,
                 "the shelf is not ordered by where the walker is standing"
  end

  # "Ideas for you, right here" used to be empty for anyone more than 3km from
  # where the suggestible routes were seeded.
  test "suggests routes further afield when nothing is nearby" do
    walker = users(:walker)
    walker.update!(current_latitude: 43.06, current_longitude: 141.35) # Sapporo
    sign_in walker

    get root_path

    assert_response :success
    assert_predicate suggested_names, :any?,
                     "a walker with nothing within reach was shown an empty shelf"
    assert_includes suggested_names, journeys(:far_route).name
  end

  test "suggests routes even with no location set at all" do
    walker = users(:walker)
    walker.update!(current_latitude: nil, current_longitude: nil)
    sign_in walker

    get root_path

    assert_predicate suggested_names, :any?
  end

  test "never suggests the same route twice when topping up" do
    walker = users(:walker)
    walker.update!(current_latitude: 35.681, current_longitude: 139.771)
    sign_in walker

    get root_path

    assert_equal suggested_names.uniq, suggested_names
  end

  test "suggests only routes cleared for it" do
    sign_in users(:walker)

    get root_path

    # meguro_loop is themed; unmeasured is not recommendable. Neither belongs
    # on a shelf of community ideas.
    assert_not_includes suggested_names, journeys(:meguro_loop).name
    assert_not_includes suggested_names, journeys(:unmeasured).name
  end

  private

  # What the carousel is actually offering, read off the page rather than the
  # controller: rails-controller-testing (and so `assigns`) is not in the
  # Gemfile, and the rendered shelf is the thing being complained about anyway.
  def suggested_names
    css_select(".carousel-item h4").map { |node| node.text.strip }
  end

  # Safari 15: no web push, no badges. Blocked by `versions: :modern`.
  OLD_SAFARI = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15 " \
               "(KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1".freeze
end
