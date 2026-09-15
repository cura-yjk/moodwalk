require "test_helper"

class JourneysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:walker)
    stub_google_places
    stub_mapbox
  end

  # The description is written off the request now, so generation must not wait
  # on the LLM -- but the journey still has to end up with the real text.
  test "create generates a route without calling the LLM, and queues the description" do
    assert_enqueued_with(job: JourneyDescriptionJob) do
      post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }
    end

    assert_not_requested :post, llm_url
    assert_response :redirect
  end

  test "the journey is saved with a readable description before the job runs" do
    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    journey = Journey.order(:created_at).last
    assert journey.description.present?, "a journey must never be saved without a description"
  end

  # Production regression: Solid Queue's tables were missing, so perform_later
  # raised and every route generation 500'd -- even though the journey was
  # already saved with a usable fallback description.
  test "a queue failure does not fail route generation" do
    # Stands in for Solid Queue's tables being absent, which is what raised here.
    JourneyDescriptionJob.define_singleton_method(:perform_later) do |*|
      raise ActiveRecord::StatementInvalid, 'relation "solid_queue_jobs" does not exist'
    end

    begin
      assert_difference -> { Journey.count }, 1 do
        post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }
      end
    ensure
      JourneyDescriptionJob.singleton_class.send(:remove_method, :perform_later)
    end

    assert_response :redirect
    assert Journey.order(:created_at).last.description.present?,
           "the journey keeps its fallback description"
  end

  test "an unknown theme is refused" do
    post journeys_path, params: { theme_key: "definitely-not-a-theme" }

    assert_redirected_to root_path
  end

  private

  # Follows LlmChat, so switching provider does not silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_google_places
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "places" => [
          place("north", 35.6836, 139.77),
          place("south", 35.6764, 139.77)
        ]
      }.to_json)
  end

  def place(id, lat, lng)
    { "id" => id, "displayName" => { "text" => id }, "location" => { "latitude" => lat, "longitude" => lng } }
  end

  def stub_mapbox
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, body: { "features" => [] }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "code" => "Ok",
        "routes" => [{ "distance" => 1600.0, "duration" => 1200.0,
                       "geometry" => "_p~iF~ps|U_ulLnnqC_mqNvxq`@", "legs" => [{ "steps" => [] }] }]
      }.to_json)
  end

  # Highlights used to be generated inside this request, so the first view of a
  # journey held it open on a live LLM call while the list on screen stayed
  # empty. Twenty journeys in production have never been viewed.
  test "highlights answer immediately and queue the written ones" do
    journey = journeys(:meguro_loop)
    journey.update!(highlights_text: nil)

    assert_enqueued_with(job: JourneyHighlightsJob) do
      get highlights_journey_path(journey), headers: { "Accept" => "application/json" }
    end

    assert_response :success
    assert_not_requested :post, llm_url
    body = JSON.parse(response.body)
    assert body["pending"], "expected the page to be told the written ones are coming"
    assert_equal journey.highlights.map(&:stringify_keys), body["highlights"]
  end

  test "highlights that are already written are served as they are" do
    journey = journeys(:meguro_loop)
    journey.update!(highlights_text: [{ "icon" => "🌸", "text" => "Cherry trees the whole way" }])

    assert_no_enqueued_jobs(only: JourneyHighlightsJob) do
      get highlights_journey_path(journey), headers: { "Accept" => "application/json" }
    end

    body = JSON.parse(response.body)
    assert_not body["pending"]
    assert_equal "Cherry trees the whole way", body["highlights"].first["text"]
  end

  # The page checks back while it waits, and each check must not queue more
  # work -- otherwise waiting for one set of highlights orders six more.
  test "checking back does not queue another generation" do
    journey = journeys(:meguro_loop)
    journey.update!(highlights_text: nil)

    assert_no_enqueued_jobs(only: JourneyHighlightsJob) do
      get highlights_journey_path(journey, poll: 1), headers: { "Accept" => "application/json" }
    end

    assert JSON.parse(response.body)["pending"]
  end

end
