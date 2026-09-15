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
end
