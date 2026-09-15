require "test_helper"

class RouteBuilderTest < ActiveSupport::TestCase
  # pick_best is what actually fixes the bug: a later, worse retry attempt
  # (e.g. a radius rescale that shrinks candidate density below viable)
  # must never overwrite an earlier attempt that succeeded. Tested directly
  # since exercising it through #call would require stubbing PoiFinder,
  # PoiSelector, RouteDescriber, and JourneyGenerator's HTTP/LLM calls all at
  # once for what is really just a small piece of decision logic.
  FakeResult = Struct.new(:success?, :journey, :error, keyword_init: true)
  FakeJourney = Struct.new(:distance_meters)

  setup do
    @builder = RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm, duration_minutes: 30)
  end

  test "keeps an earlier success instead of a later failure" do
    success = FakeResult.new(success?: true, journey: FakeJourney.new(2400))
    failure = FakeResult.new(success?: false, error: "Could not find a suitable set of waypoints")

    assert_equal success, @builder.send(:pick_best, success, failure)
  end

  test "replaces a failure with a later success" do
    failure = FakeResult.new(success?: false, error: "no candidates")
    success = FakeResult.new(success?: true, journey: FakeJourney.new(2400))

    assert_equal success, @builder.send(:pick_best, failure, success)
  end

  test "between two successes, keeps whichever is closer to the target distance" do
    target = @builder.instance_variable_get(:@target_distance)
    closer = FakeResult.new(success?: true, journey: FakeJourney.new(target + 50))
    farther = FakeResult.new(success?: true, journey: FakeJourney.new(target + 5000))

    assert_equal closer, @builder.send(:pick_best, farther, closer)
    assert_equal closer, @builder.send(:pick_best, closer, farther)
  end

  test "with no current best yet, takes whatever the first attempt was" do
    failure = FakeResult.new(success?: false, error: "no candidates")
    assert_equal failure, @builder.send(:pick_best, nil, failure)
  end

  # select_waypoints decides loop vs. one-way from the real candidates (via
  # PoiSelector's actual spread scoring) instead of a coin flip - exercised
  # directly with real POI data rather than mocking PoiSelector, since the
  # whole point is that the decision follows from real spread math.
  test "chooses a loop when real candidates spread out enough" do
    pois = [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "south", category: "park", distance_meters: 450, bearing: :south)
    ]

    selection = @builder.send(:select_waypoints, pois)

    assert selection.success?
    assert @builder.instance_variable_get(:@round_trip)
  end

  test "falls back to one-way when real candidates cluster in one direction" do
    pois = [
      poi(id: "north-near", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "north-far", category: "park", distance_meters: 450, bearing: :north)
    ]

    selection = @builder.send(:select_waypoints, pois)

    assert selection.success?
    assert_not @builder.instance_variable_get(:@round_trip)
  end

  # --- LLM off the critical path -------------------------------------------
  #
  # RouteDescriber used to run mid-pipeline and abort the build on failure, so
  # an OpenAI outage took down route generation even with Google and Mapbox
  # both healthy. These exercise #call end-to-end with the HTTP layer stubbed.

  test "still returns a route when the LLM is unavailable" do
    stub_happy_geo_apis
    stub_llm_failure

    result = build_toward(duration_minutes: 30)

    assert result.success?, "an LLM outage must not fail a route: #{result.error}"
    assert result.journey.present?
    assert result.journey.description.present?, "expected a fallback description"
  end

  test "the fallback description follows the tone rules the prompt sets" do
    stub_happy_geo_apis
    stub_llm_failure

    description = build_toward(duration_minutes: 30).journey.description

    assert_no_match(/!/, description, "no exclamation points")
    # The prompt forbids naming places; the POIs here are named "north"/"south".
    assert_no_match(/north|south/i, description, "must not name specific places")
    assert_operator description.split(/[.!?]/).reject(&:blank?).size, :<=, 2, "1-2 sentences"
  end

  # The LLM is no longer called during generation at all -- it was two thirds
  # of a route's build time. JourneyDescriptionJob swaps the real description
  # in afterwards (see test/jobs/journey_description_job_test.rb).
  test "never calls the LLM during generation, even when it is available" do
    stub_happy_geo_apis
    stub_llm_success("Water on one side, trees on the other.")

    result = build_toward(duration_minutes: 30)

    assert result.success?
    assert_not_requested :post, llm_url
    assert_equal RouteDescriber.fallback_for(theme_key: :calm, waypoints: result.waypoints),
                 result.journey.description
  end

  # The retry loop is where the LLM used to be called repeatedly -- once per
  # attempt, with all but one description thrown away.
  test "no LLM call however many attempts the retry loop takes" do
    stub_happy_geo_apis(distance: 100_000) # nowhere near target -> forces every retry
    stub_llm_success("A quiet stretch.")

    result = build_toward(duration_minutes: 30)

    assert result.success?
    # Guard against this passing trivially: prove the retry loop really ran.
    assert_requested :get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/},
                     times: RouteBuilder::MAX_ATTEMPTS
    assert_not_requested :post, llm_url
  end

  # Each category is fetched on its own thread now; they must all still arrive.
  test "gathers every theme category despite fetching them concurrently" do
    stub_happy_geo_apis

    result = build_toward(duration_minutes: 30)

    assert result.success?
    THEMES[:calm][:categories].each do |category|
      assert_requested :post, PoiFinder::NEARBY_SEARCH_URL,
                       body: hash_including("includedTypes" => [category]), at_least_times: 1
    end
  end

  test "a route-building failure still fails, and never reaches the LLM" do
    stub_nearby_search_empty
    stub_llm_success("unused")

    result = build_toward(duration_minutes: 30)

    assert_not result.success?
    assert_not_requested :post, llm_url
  end

  private

  # Follows LlmChat, so switching provider does not silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def poi(id:, category:, distance_meters:, bearing:)
    lat = @builder.instance_variable_get(:@lat)
    lng = @builder.instance_variable_get(:@lng)
    meters_per_degree_lat = 111_320.0
    meters_per_degree_lng = 111_320.0 * Math.cos(lat * Math::PI / 180)

    poi_lat, poi_lng = case bearing
                       when :north
                         [lat + (distance_meters / meters_per_degree_lat), lng]
                       when :south
                         [lat - (distance_meters / meters_per_degree_lat), lng]
                       end

    { id: id, name: id, category: category, lat: poi_lat, lng: poi_lng, distance_meters: distance_meters }
  end

  def build_toward(duration_minutes:)
    RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm, duration_minutes: duration_minutes).call
  end

  # Two POIs spread north/south so PoiSelector yields a viable loop.
  def stub_happy_geo_apis(distance: 2400.0)
    THEMES[:calm][:categories].each do |category|
      stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
        .with(body: hash_including("includedTypes" => [category]))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          "places" => [
            google_place(id: "#{category}-north", name: "north", lat: 35.6836, lng: 139.77),
            google_place(id: "#{category}-south", name: "south", lat: 35.6764, lng: 139.77)
          ]
        }.to_json)
    end

    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, body: { "features" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "code" => "Ok",
        "routes" => [{ "distance" => distance, "duration" => distance / 1.33,
                       "geometry" => "encodedpolyline", "legs" => [{ "steps" => [] }] }]
      }.to_json)
  end

  def stub_nearby_search_empty
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, body: { "places" => [] }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_llm_failure
    stub_request(:post, llm_url)
      .to_return(status: 429, headers: { "Content-Type" => "application/json" }, body: {
        "error" => { "message" => "You have no credits remaining.", "code" => "credit_balance_exhausted" }
      }.to_json)
  end

  def stub_llm_success(description)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { description: description }.to_json }] } }]
      }.to_json)
  end

  def google_place(id:, name:, lat:, lng:)
    { "id" => id, "displayName" => { "text" => name }, "location" => { "latitude" => lat, "longitude" => lng } }
  end
end
