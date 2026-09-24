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

  # Selection is deterministic, so before this the same doorstep, theme and
  # duration produced the identical walk every time: a user who did not fancy
  # what we suggested and asked again got it straight back.
  test "asking twice from the same doorstep does not suggest the same walk twice" do
    stub_many_places

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }
    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    routed = recorded_waypoints
    assert_equal routed.size, routed.uniq.size,
                 "asking again routed through the same waypoints: #{routed.first}"
  end

  test "the same seed reproduces the same walk, so variety is not randomness" do
    stub_many_places

    first = PoiSelector.new(**selector_args(variety_seed: 3)).call.waypoints
    second = PoiSelector.new(**selector_args(variety_seed: 3)).call.waypoints

    assert_equal first.map { |w| w[:id] }, second.map { |w| w[:id] }
  end

  # Production held 41 journeys across 35 distinct polylines.
  test "a route we already have is reused rather than saved a second time" do
    existing = journeys(:meguro_loop)
    stub_mapbox(geometry: existing.encoded_polyline)

    assert_no_difference -> { Journey.count } do
      post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }
    end

    assert_redirected_to new_journey_walk_path(existing)
  end

  test "reusing a route does not pay to describe it again" do
    stub_mapbox(geometry: journeys(:meguro_loop).encoded_polyline)

    assert_no_enqueued_jobs only: JourneyDescriptionJob do
      post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }
    end
  end

  # --- when no route can be built -----------------------------------------
  #
  # The fallback used to reach up to 3km for a route, consider only curated
  # ones, and then settle for any theme or the newest route in the database -
  # a silent swap for something the user didn't pick, possibly in another
  # city. Now it's a walk that answers the same request, or an honest message.

  test "reuses a saved walk of the same theme and time that starts close by" do
    stub_nothing_nearby

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to new_journey_walk_path(journeys(:meguro_loop))
  end

  test "reuses generated walks too, not only curated ones" do
    stub_nothing_nearby
    journeys(:meguro_loop).update!(recommendable: false)

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to new_journey_walk_path(journeys(:meguro_loop))
  end

  test "doesn't reuse a walk that starts more than a few minutes away" do
    stub_nothing_nearby
    users(:walker).update!(current_latitude: 35.684) # ~450m north of the walk's start

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to root_path
  end

  test "doesn't reuse a walk that retraces its own streets" do
    stub_nothing_nearby
    out = (0..10).map { |i| [35.68 + (i * 0.0005), 139.77] }
    journeys(:meguro_loop).update!(encoded_polyline: encode_polyline(out + out.reverse))

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to root_path
  end

  test "doesn't swap in a walk of another theme" do
    stub_nothing_nearby

    post journeys_path, params: { theme_key: "recharge", duration_minutes: 20 }

    assert_redirected_to root_path
  end

  # --- what to suggest instead ---------------------------------------------
  #
  # Only themes checked from this spot are named. A saved walk ready nearby
  # proves it for free; otherwise one grouped Google search per theme shows
  # there's enough within reach to build from.

  test "names a theme that has a saved walk ready nearby, without asking Google about it" do
    stub_nothing_nearby

    post journeys_path, params: { theme_key: "refresh", duration_minutes: 20 }

    assert_equal "No scenic spots within a 20-minute walk from here. Calm has places within reach.", flash[:notice]
    assert_not_requested :post, PoiFinder::NEARBY_SEARCH_URL,
                         body: hash_including("includedPrimaryTypes" => THEMES[:calm][:categories])
  end

  test "names a theme with enough places within reach, and not one with too few" do
    move_away_from_saved_walks
    stub_nothing_nearby
    stub_grouped_search(:cheerful, places: 2)
    stub_grouped_search(:refresh, places: 1)

    post journeys_path, params: { theme_key: "recharge", duration_minutes: 20 }

    assert_equal "No nature spots within a 20-minute walk from here. Cheerful has places within reach.", flash[:notice]
  end

  test "stops looking once two themes are named" do
    move_away_from_saved_walks
    stub_nothing_nearby
    stub_grouped_search(:calm, places: 3)
    stub_grouped_search(:cheerful, places: 3)

    post journeys_path, params: { theme_key: "recharge", duration_minutes: 20 }

    assert_equal "No nature spots within a 20-minute walk from here. " \
                 "Calm and Cheerful have places within reach.", flash[:notice]
    assert_not_requested :post, PoiFinder::NEARBY_SEARCH_URL,
                         body: hash_including("includedPrimaryTypes" => THEMES[:refresh][:categories])
  end

  test "doesn't suggest the theme that was just tried" do
    stub_nothing_nearby
    stub_grouped_search(:calm, places: 3)
    journeys(:meguro_loop).update!(theme_key: "refresh")

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_no_match(/Calm/, flash[:notice])
  end

  test "when nothing else is within reach either, suggests a longer walk" do
    move_away_from_saved_walks
    stub_nothing_nearby

    post journeys_path, params: { theme_key: "recharge", duration_minutes: 20 }

    assert_equal "No nature spots within a 20-minute walk from here. Try a longer walk, or No rush.", flash[:notice]
  end

  test "at the longest walk on offer, suggests only No rush" do
    move_away_from_saved_walks
    stub_nothing_nearby

    post journeys_path, params: { theme_key: "recharge", duration_minutes: JourneysController::DURATION_CHOICES.max }

    assert_match(/Try No rush\.\z/, flash[:notice])
  end

  test "with no rush and nothing else nearby, says so" do
    move_away_from_saved_walks
    stub_nothing_nearby

    post journeys_path, params: { theme_key: "refresh" }

    assert_equal "No scenic spots nearby. Nothing else is close by right now either.", flash[:notice]
  end

  # --- requests the picker can't make --------------------------------------

  # A duration of 0 or less used to reach RouteBuilder: a zero search radius,
  # a division by zero in ShortlistRouter, a silent failure, and a banner
  # about a "0-minute walk".
  test "a duration the picker doesn't offer is refused before anything is searched" do
    [0, -5, 45].each do |minutes|
      post journeys_path, params: { theme_key: "calm", duration_minutes: minutes }

      assert_redirected_to root_path
      assert_equal "Pick how long you have to get started.", flash[:alert]
    end
    assert_not_requested :post, PoiFinder::NEARBY_SEARCH_URL
  end

  # --- when Google can't be reached ------------------------------------------
  #
  # An outage used to read as "nothing nearby, try a longer walk" - advice
  # that's false, and sends the user off to try things that can't work either.

  test "says so when places can't be searched, rather than that there are none" do
    move_away_from_saved_walks
    stub_places_outage

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to root_path
    assert_equal "We couldn't reach our map services just now. Please try again in a moment.", flash[:notice]
  end

  test "says so when routes can't be worked out, rather than that nothing is nearby" do
    move_away_from_saved_walks
    stub_many_places
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/})
      .to_return(status: 503, body: "<html>Service Unavailable</html>")

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to root_path
    assert_equal "We couldn't reach our map services just now. Please try again in a moment.", flash[:notice]
  end

  test "still offers a saved walk nearby while places can't be searched" do
    stub_places_outage

    post journeys_path, params: { theme_key: "calm", duration_minutes: 20 }

    assert_redirected_to new_journey_walk_path(journeys(:meguro_loop))
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

  # Well clear of every fixture's start, so no saved walk counts as nearby.
  def move_away_from_saved_walks
    users(:walker).update!(current_latitude: 35.70, current_longitude: 139.80)
  end

  # Answers the one-request check of a whole theme's categories. Registered
  # after stub_nothing_nearby, so it takes precedence for this theme only.
  def stub_grouped_search(theme_key, places:)
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .with(body: hash_including("includedPrimaryTypes" => THEMES[theme_key][:categories]))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "places" => Array.new(places) { |i| place("#{theme_key}-#{i}", 35.70, 139.80) } }.to_json)
  end

  # A gateway error page rather than Google's JSON, the way an outage looks.
  def stub_places_outage
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL).to_return(status: 503, body: "<html>Service Unavailable</html>")
  end

  def stub_nothing_nearby
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { "places" => [] }.to_json)
  end

  # Google's encoded polyline format, from [lat, lng] pairs - the inverse of
  # PolylineDecoder, for building a route shape a test needs.
  def encode_polyline(points)
    previous = [0, 0]
    points.map do |point|
      scaled = point.map { |degrees| (degrees * 1e5).round }
      deltas = scaled.zip(previous).map { |value, last| value - last }
      previous = scaled
      deltas.map { |delta| encode_polyline_value(delta) }.join
    end.join
  end

  def encode_polyline_value(value)
    value = value.negative? ? ~(value << 1) : value << 1
    chunks = []
    while value >= 0x20
      chunks << (((value & 0x1f) | 0x20) + 63).chr
      value >>= 5
    end
    chunks << (value + 63).chr
    chunks.join
  end

  def selector_args(variety_seed:)
    pois = 8.times.map do |i|
      point = GeoDistance.destination_point(35.68, 139.77, 250 + (i * 120), (i * 47) % 360)
      { id: "poi-#{i}", name: "P#{i}", category: %w[park garden lake][i % 3],
        lat: point[:lat], lng: point[:lng], distance_meters: 250 + (i * 120) }
    end

    { lat: 35.68, lng: 139.77, pois: pois, target_distance_meters: 1600,
      round_trip: true, variety_seed: variety_seed }
  end

  def place(id, lat, lng)
    { "id" => id, "displayName" => { "text" => id }, "location" => { "latitude" => lat, "longitude" => lng } }
  end

  # Deliberately NOT the journeys(:meguro_loop) polyline: an identical route is
  # now reused rather than saved again, so a stub handing back the fixture's own
  # geometry would quietly turn every "create" test into a "reuse" test.
  GENERATED_POLYLINE = "_p~iF~ps|U_ulLnnqC".freeze

  def stub_mapbox(geometry: GENERATED_POLYLINE)
    @routed = []

    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, body: { "features" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    # Recorded here rather than read back off WebMock's request registry: that
    # registry is keyed by request signature, so two identical calls collapse
    # into one entry and a "did we route the same way twice" assertion can
    # never fail. This keeps one entry per call, identical or not.
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/}).to_return do |request|
      @routed << request.uri.path.split("/").last
      { status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "code" => "Ok",
        "routes" => [{ "distance" => 1600.0, "duration" => 1200.0,
                       "geometry" => geometry, "legs" => [{ "steps" => [] }] }]
      }.to_json }
    end
  end

  # Enough spread-out candidates that PoiSelector has a real shortlist to pick
  # from; the two-POI default leaves it only one combination and nothing to vary.
  def stub_many_places
    remove_request_stub(@places_stub) if @places_stub
    places = 8.times.map do |i|
      point = GeoDistance.destination_point(35.68, 139.77, 250 + (i * 120), (i * 47) % 360)
      place("poi-#{i}", point[:lat], point[:lng])
    end

    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "places" => places }.to_json)
  end

  # The coordinate list Mapbox was asked to route through, one entry per call.
  def recorded_waypoints
    @routed
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
