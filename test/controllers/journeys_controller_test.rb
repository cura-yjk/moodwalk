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

    assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
    assert_response :redirect
  end

  test "the journey is saved with a readable description before the job runs" do
    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    journey = Journey.order(:created_at).last
    assert journey.description.present?, "a journey must never be saved without a description"
  end

  test "an unknown theme is refused" do
    post journeys_path, params: { theme_key: "definitely-not-a-theme" }

    assert_redirected_to root_path
  end

  private

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
