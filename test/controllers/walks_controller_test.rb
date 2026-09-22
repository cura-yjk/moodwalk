require "test_helper"

class WalksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:walker) }

  test "requires authentication" do
    sign_out users(:walker)
    get walk_path(walks(:completed_walk))

    assert_redirected_to new_user_session_path
  end

  # Regression: #share_quote used a bare Walk.find while every other action
  # scoped through current_user.walks, so any signed-in user could read (and
  # write to) someone else's walk.
  test "share_quote refuses another user's walk" do
    post share_quote_walk_path(walks(:other_users_walk)), params: { reflection: "hi" }

    assert_response :not_found
    assert_nil walks(:other_users_walk).reload.share_quote,
               "the other user's walk must not be written to"
  end

  test "share_quote returns the already-generated quote for your own walk" do
    walk = walks(:completed_walk)
    walk.update!(share_quote: "A quiet hour by the river.")

    post share_quote_walk_path(walk), params: { reflection: "nice" }

    assert_response :success
    assert_equal "A quiet hour by the river.", response.parsed_body["quote"]
  end

  # The memory card renders an empty <p> and fills it from this endpoint, so a
  # failing LLM used to leave the quote area permanently blank -- and returned
  # the provider's raw error (API key fragments included) to the browser.
  test "share_quote falls back to a plain quote when the LLM is unavailable" do
    stub_llm_failure
    walk = walks(:completed_walk)
    walk.update!(share_quote: nil)

    post share_quote_walk_path(walk), params: { mood_after: walk.mood_after, reflection: "x" }

    assert_response :success
    quote = response.parsed_body["quote"]
    assert quote.present?, "the memory card must never be left with an empty quote"
    assert_nil response.parsed_body["error"]
    assert_no_match(/sk-|anthropic|api key/i, response.body, "must not leak provider detail to the client")
  end

  # share_quote is generated once and reused forever, so persisting a
  # stand-in would permanently deny this walk a real quote.
  test "share_quote does not persist the fallback" do
    stub_llm_failure
    walk = walks(:completed_walk)
    walk.update!(share_quote: nil)

    post share_quote_walk_path(walk), params: { mood_after: walk.mood_after }

    assert_response :success
    assert_nil walk.reload.share_quote, "the fallback must not be cached"
  end

  test "share_quote persists a real LLM quote" do
    stub_llm_success("Cold air, and the river going the other way.")
    walk = walks(:completed_walk)
    walk.update!(share_quote: nil)

    post share_quote_walk_path(walk), params: { mood_after: walk.mood_after }

    assert_response :success
    assert_equal "Cold air, and the river going the other way.", walk.reload.share_quote
  end

  test "show refuses another user's walk" do
    get walk_path(walks(:other_users_walk))

    assert_response :not_found
  end

  test "memory refuses another user's walk" do
    get memory_walk_path(walks(:other_users_walk))

    assert_response :not_found
  end

  # Regression: mood_after was permitted straight from params with no
  # validation, and the views then raised KeyError rendering its icon --
  # locking the user out of their own walk list.
  test "update rejects an unknown mood instead of persisting it" do
    walk = walks(:completed_walk)

    patch walk_path(walk), params: { walk: { mood_after: "Furious" } }

    assert_response :unprocessable_entity
    assert_equal "Calm", walk.reload.mood_after
  end

  test "update accepts a known mood" do
    walk = walks(:completed_walk)

    patch walk_path(walk), params: { walk: { mood_after: "Good", reflection: "Felt lighter." } }

    assert_redirected_to memory_walk_path(walk)
    assert_equal "Good", walk.reload.mood_after
  end

  test "index renders with lifetime stats" do
    get walks_path

    assert_response :success
  end

  test "index renders the saved-journeys filter" do
    users(:walker).saved_journeys.create!(journey: journeys(:unmeasured))

    get walks_path(filter: "saved")

    assert_response :success
    assert_select ".route-card-duration", false,
                  "a journey with no duration shouldn't render a duration chip"
  end

  # The card had two branches and only the photo-less one carried the time and
  # the route name -- so attaching a photo to a walk silently stripped both off
  # its card, and a history of photographed walks showed neither.
  test "a walk with a photo of its own still shows its route name and time" do
    walk = walks(:completed_walk)
    walk.photo.attach(
      io: Rails.root.join("test/fixtures/files/walk_photo.png").open,
      filename: "walk_photo.png", content_type: "image/png"
    )

    get walks_path

    assert_response :success
    # Asserted on that walk's own card. The signed-in user has more than one,
    # and only this one carries a photo -- a plain ".route-card-title" search
    # finds the other card's and passes while this one renders empty.
    assert_select card_for(walk) + " .route-card-title", text: walk.journey.name
    assert_select card_for(walk) + " .walk-time"
  end

  test "a walk with no photo of its own shows them too" do
    walk = walks(:in_progress_walk)
    assert_not walk.photo.attached?

    get walks_path

    assert_select card_for(walk) + " .route-card-title", text: walk.journey.name
    assert_select card_for(walk) + " .walk-time"
  end

  test "every walk on the page keeps its name and its time" do
    walks(:completed_walk).photo.attach(
      io: Rails.root.join("test/fixtures/files/walk_photo.png").open,
      filename: "walk_photo.png", content_type: "image/png"
    )

    get walks_path

    cards = css_select(".walk-card-flip").size
    assert_operator cards, :>, 1, "needs more than one card for this to mean anything"
    assert_select ".walk-thumbnail .route-card-title", count: cards
    assert_select ".walk-thumbnail .walk-time", count: cards
  end

  # The card used to call JourneyImages.sample, which picks at random with no
  # journey to key off -- so a saved route showed a different photo on every
  # render, and looked like the photos were failing to load.
  test "a saved journey keeps the same photo across renders" do
    journey = journeys(:meguro_loop)
    users(:walker).saved_journeys.create!(journey: journey)

    photos = 2.times.map do
      get walks_path(filter: "saved")
      assert_response :success
      css_select(".community-image").first["src"]
    end

    assert_equal photos.first, photos.last, "the saved card changed photo between renders"
    assert_equal journey.placeholder_image, photos.first, "the card is not showing this journey's photo"
  end

  # #new renders the journey's duration and picks an alternate journey. The
  # alternate lookup used to load the whole journeys table via Array#sample.
  test "new renders the start-walk screen with an alternate suggestion" do
    get new_journey_walk_path(journeys(:meguro_loop))

    assert_response :success
  end

  test "new renders for a journey with no distance or duration" do
    get new_journey_walk_path(journeys(:unmeasured))

    assert_response :success
  end

  test "create starts a walk and marks the journey recommendable" do
    assert_difference -> { users(:walker).walks.count }, 1 do
      post journey_walks_path(journeys(:meguro_loop)), params: { walk: { mood_before: "Calm" } }
    end

    assert journeys(:meguro_loop).reload.recommendable
    assert_equal "Calm", users(:walker).walks.order(:created_at).last.mood_before
  end

  # An unrecognized mood is dropped rather than blocking the walk from starting.
  test "create ignores an unknown mood_before" do
    post journey_walks_path(journeys(:meguro_loop)), params: { walk: { mood_before: "Furious" } }

    walk = users(:walker).walks.order(:created_at).last
    assert_nil walk.mood_before
    assert_redirected_to walk_path(walk)
  end

  test "track stores breadcrumbs for your own walk" do
    walk = walks(:in_progress_walk)

    assert_difference -> { walk.walk_track_points.count }, 2 do
      post track_walk_path(walk), params: {
        points: [
          { latitude: 35.68, longitude: 139.77, recorded_at: 1.minute.ago },
          { latitude: 35.681, longitude: 139.77, recorded_at: Time.current }
        ]
      }
    end

    assert_response :no_content
  end

  test "complete finalizes the walk and redirects to the reflection form" do
    walk = walks(:in_progress_walk)

    patch complete_walk_path(walk), params: { walk: { actual_distance: "1.5", actual_steps: "1900" } }

    assert_redirected_to edit_walk_path(walk)
    assert walk.reload.completed_at.present?
  end

  private

  # A walk's own card, addressed by the memory URL it carries.
  def card_for(walk)
    %([data-walk-card-memory-url-value="#{memory_walk_path(walk)}"])
  end

  # Follows LlmChat, so switching provider does not silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm_failure
    stub_request(:post, llm_url)
      .to_return(status: 429, headers: { "Content-Type" => "application/json" }, body: {
        "type" => "error",
        "error" => { "type" => "authentication_error", "message" => "invalid x-api-key sk-ant-abc123" }
      }.to_json)
  end

  def stub_llm_success(quote)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { quote: quote }.to_json }] } }]
      }.to_json)
  end
end
