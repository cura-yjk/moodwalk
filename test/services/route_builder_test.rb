require "test_helper"

class RouteBuilderTest < ActiveSupport::TestCase
  MAPBOX_DIRECTIONS = %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/}
  MAPBOX_REVERSE_GEOCODE = %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse}
  FakeJourney = Struct.new(:estimated_duration_seconds, :overlap_ratio)

  setup do
    @builder = RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm, duration_minutes: 30)
  end

  # Loop vs. one-way is decided from the real candidates, not a coin flip -
  # exercised with real POI data through the real selector, with only Mapbox
  # stubbed, since the whole point is that the decision follows from real
  # geometry.
  test "routes a loop when real candidates let it go round the start" do
    routed = route_with(north_and(:east)) { 0.0 }

    assert routed[:calls].first[:round_trip]
    assert @builder.instance_variable_get(:@round_trip)
  end

  test "routes one-way when the only loop would double back through the start" do
    routed = route_with(north_and(:south)) { 0.0 }

    assert_not routed[:calls].first[:round_trip]
  end

  test "routes one-way when real candidates cluster in one direction" do
    pois = [
      poi(id: "north-near", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "north-far", category: "park", distance_meters: 450, bearing: :north)
    ]

    routed = route_with(pois) { 0.0 }

    assert_not routed[:calls].first[:round_trip]
  end

  # Whether a loop retraces itself only shows once Mapbox has routed it. From
  # a real doorstep every loop option re-walked 24-27% of itself, while a
  # one-way walk from the same places re-walked 3% - and the loop was kept,
  # because the shape was settled before anything was routed.
  test "routes the one-way options when every loop option is retraced" do
    routed = route_with { |round_trip| round_trip ? 0.3 : 0.02 }

    assert_equal [true] * ShortlistRouter::MAX_ROUTINGS, routed[:calls].first(3).pluck(:round_trip)
    assert_not routed[:calls].last[:round_trip]
    assert_in_delta 0.02, routed[:result].journey.overlap_ratio
    assert_not @builder.instance_variable_get(:@round_trip), "the title must say one-way too"
  end

  test "doesn't route one-way options when a loop passes" do
    routed = route_with { |round_trip| round_trip ? 0.02 : 0.0 }

    assert(routed[:calls].all? { |call| call[:round_trip] })
  end

  test "keeps the retraced loop when the one-way options are worse" do
    routed = route_with { |round_trip| round_trip ? 0.2 : 0.4 }

    assert_in_delta 0.2, routed[:result].journey.overlap_ratio
    assert @builder.instance_variable_get(:@round_trip)
  end

  # --- re-walked streets ---------------------------------------------------
  #
  # Whether a route re-walks its own streets only shows in the route Mapbox
  # returns - a spur in and out of a park, say - never in the waypoint plan.
  # So build_from routes the selector's next-best waypoints when the first
  # route re-walks too much, from the places already fetched. The rules for
  # choosing between routes are LeastRewalkedRoute's, tested there; this
  # checks the selector's alternatives actually reach it.

  test "routes the next-best waypoints when the first route re-walks too much" do
    overlaps = [0.3, 0.05]
    routed = route_with { overlaps.shift || 0.0 }

    assert_equal 2, routed[:calls].size
    assert_in_delta 0.05, routed[:result].journey.overlap_ratio
    assert_equal routed[:calls].last[:waypoints], routed[:result].waypoints
  end

  # Routing more than one option is where the LLM used to be called
  # repeatedly -- once per attempt, with all but one description thrown away.
  test "no LLM call however many routes it tries" do
    stub_happy_geo_apis(distance: 100_000) # nowhere near target -> every option gets routed
    stub_llm_success("A quiet stretch.")

    result = build_toward(duration_minutes: 30)

    assert result.success?
    # Guard against this passing trivially: prove more than one route was tried.
    assert_requested :get, MAPBOX_DIRECTIONS, at_least_times: 2
    assert_not_requested :post, llm_url
  end

  # --- cost per generation -------------------------------------------------
  #
  # A route the wrong length used to send the whole search back to Google at a
  # rescaled radius - a full set of category searches per retry, measured at
  # about 14 per route - and the rescale couldn't fix the length anyway, since
  # the selector aimed at the same target from much the same places.

  test "a route the wrong length is re-picked from the places already found" do
    stub_happy_geo_apis(distance: 100_000)

    build_toward(duration_minutes: 30)

    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: THEMES[:calm][:categories].size
    assert_requested :get, MAPBOX_DIRECTIONS, times: ShortlistRouter::MAX_ROUTINGS
  end

  # Measured across three areas: every walk that searched wider for a set
  # duration came back 30-60 minutes long for a 20-minute request, built
  # through places 1-2.5km away. A walk of that length can't reach them, and
  # saying so beats selling a 46-minute walk as a 20-minute one.
  test "with a duration, doesn't search beyond what a walk that long can reach" do
    stub_nearby_search_empty

    build_toward(duration_minutes: 30)

    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: THEMES[:calm][:categories].size
  end

  test "with no rush, searches wider when there are too few places to build a route" do
    stub_nearby_search_empty

    RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm).call

    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL,
                     times: THEMES[:calm][:categories].size * RouteBuilder::MAX_ATTEMPTS
  end

  # A one-way walk can end as far out as the whole target distance allows,
  # straight-line - searching only half the target out (the loop's reach)
  # left a 10-minute walk nothing but parks 200-330m away, which made every
  # two-stop route far too long.
  test "searches as far out as a one-way walk of the target length can reach" do
    stub_happy_geo_apis

    build_toward(duration_minutes: 10)

    reach = 10 * RouteBuilder::WALKING_METERS_PER_MINUTE / PoiSelector::DETOUR_FACTOR
    assert_requested(:post, PoiFinder::NEARBY_SEARCH_URL, at_least_times: 1) do |request|
      JSON.parse(request.body).dig("locationRestriction", "circle", "radius").round == reach.round
    end
  end

  # A route on target by distance can still read long in minutes, and the
  # minutes are what the walker sees.
  test "a route the right distance but the wrong time is re-picked" do
    stub_happy_geo_apis(distance: 2400.0, duration: 45 * 60)

    build_toward(duration_minutes: 30)

    assert_requested :get, MAPBOX_DIRECTIONS, at_least_times: 2
  end

  # JourneysController tells "nothing nearby" apart from "couldn't look":
  # only the first is worth suggesting a longer walk for.
  test "a failed search for places is reported as unavailable, not as nothing nearby" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL).to_return(status: 503, body: "<html>down</html>")

    result = build_toward(duration_minutes: 30)

    assert_not result.success?
    assert result.unavailable
  end

  # Once Mapbox is down, asking it again only adds failing calls, and a wider
  # search for places couldn't be routed either.
  test "a Mapbox outage is reported as unavailable, after one call" do
    stub_happy_geo_apis
    stub_request(:get, MAPBOX_DIRECTIONS).to_return(status: 503, body: "<html>down</html>")

    result = RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm).call

    assert_not result.success?
    assert result.unavailable
    assert_requested :get, MAPBOX_DIRECTIONS, times: 1
    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: THEMES[:calm][:categories].size
  end

  test "an empty search is nothing nearby, not unavailable" do
    stub_nearby_search_empty

    assert_not build_toward(duration_minutes: 30).unavailable
  end

  # With no duration a failed pass searches wider, and every pass could route
  # both shapes' shortlists: up to 18 Mapbox calls for one tap, all failing.
  test "a build that keeps failing stops asking Mapbox after MAX_ROUTINGS_PER_BUILD" do
    stub_happy_geo_apis
    stub_request(:get, MAPBOX_DIRECTIONS)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "code" => "NoRoute", "message" => "No route found" }.to_json)

    result = RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm).call

    assert_not result.success?
    assert_requested :get, MAPBOX_DIRECTIONS, times: RouteBuilder::MAX_ROUTINGS_PER_BUILD
  end

  # The start never moves between the routes tried, so neither does its
  # neighbourhood.
  test "looks up the neighbourhood once however many routes it tries" do
    stub_happy_geo_apis(distance: 100_000)

    result = build_toward(duration_minutes: 30)

    assert_requested :get, MAPBOX_REVERSE_GEOCODE, times: 1
    assert_equal "Meguro", result.journey.location_name
  end

  # Each category is fetched on its own thread now; they must all still arrive.
  test "gathers every theme category despite fetching them concurrently" do
    stub_happy_geo_apis

    result = build_toward(duration_minutes: 30)

    assert result.success?
    THEMES[:calm][:categories].each do |category|
      assert_requested :post, PoiFinder::NEARBY_SEARCH_URL,
                       body: hash_including("includedPrimaryTypes" => [category]), at_least_times: 1
    end
  end

  # One themed generation costs one Google request per category, once per retry
  # attempt -- measured at 24 for cheerful's eight categories. The same ground
  # gets searched again whenever a walk is turned down and re-asked for, which
  # is now something the app actively invites (see PoiSelector's variety pool).
  test "asking again from the same doorstep costs nothing at Google" do
    with_memory_cache do
      stub_happy_geo_apis

      build_toward(duration_minutes: 30)
      first_pass = places_requested

      build_toward(duration_minutes: 30)

      assert_operator first_pass, :>, 0, "the first generation should have searched"
      assert_equal first_pass, places_requested, "asking again went back to Google"
    end
  end

  # The generated route used to be called after its theme, so every calm walk
  # in the app was called "Calm".
  test "a built route is named after itself, not after its theme" do
    stub_happy_geo_apis

    result = build_toward(duration_minutes: 30)

    assert result.success?
    assert_not_equal THEMES[:calm][:label], result.journey.name,
                     "the route is still named after its theme"
    assert_match(/Loop|Walk/, result.journey.name)
  end

  test "a route-building failure still fails, and never reaches the LLM" do
    stub_nearby_search_empty
    stub_llm_success("unused")

    result = build_toward(duration_minutes: 30)

    assert_not result.success?
    assert_not_requested :post, llm_url
  end

  private

  # The test environment runs on :null_store, which forgets everything it is
  # given -- so a caching assertion made against it would pass without a cache.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  def places_requested
    WebMock::RequestRegistry.instance.times_executed(
      WebMock::RequestPattern.new(:post, PoiFinder::NEARBY_SEARCH_URL)
    )
  end

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
                       when :east
                         [lat, lng + (distance_meters / meters_per_degree_lng)]
                       end

    { id: id, name: id, category: category, lat: poi_lat, lng: poi_lng, distance_meters: distance_meters }
  end

  # Runs build_from on real POIs through the real selector, with each Mapbox
  # routing answered by the block: given the shape being routed, it returns
  # how much of the route re-walks itself, or :rejected for a route Mapbox
  # turns down. Every route comes back exactly the length asked for. Returns
  # the result and each routing's waypoints and shape.
  def route_with(pois = shortlist_pois, &overlap_for)
    calls = []
    seconds = 30 * 60
    @builder.define_singleton_method(:generate_journey) do |waypoints, round_trip:|
      calls << { waypoints: waypoints, round_trip: round_trip }
      overlap = overlap_for.call(round_trip)
      next JourneyGenerator::Result.new(success?: false, error: "route backtracks on itself (dead end / u-turn)") if overlap == :rejected

      JourneyGenerator::Result.new(success?: true, journey: FakeJourney.new(seconds, overlap))
    end

    { result: @builder.send(:build_from, pois), calls: calls }
  end

  def north_and(other)
    [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: other.to_s, category: "park", distance_meters: 450, bearing: other)
    ]
  end

  # Enough candidates for the selector to have a full shortlist of options.
  def shortlist_pois
    [
      poi(id: "north", category: "park", distance_meters: 400, bearing: :north),
      poi(id: "east", category: "park", distance_meters: 450, bearing: :east),
      poi(id: "north-far", category: "garden", distance_meters: 800, bearing: :north),
      poi(id: "east-far", category: "garden", distance_meters: 900, bearing: :east)
    ]
  end

  def build_toward(duration_minutes:)
    RouteBuilder.new(lat: 35.68, lng: 139.77, theme_key: :calm, duration_minutes: duration_minutes).call
  end

  # Two POIs spread north/south so PoiSelector yields a viable loop.
  def stub_happy_geo_apis(distance: 2400.0, duration: distance / 1.33)
    THEMES[:calm][:categories].each do |category|
      stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
        .with(body: hash_including("includedPrimaryTypes" => [category]))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          "places" => [
            google_place(id: "#{category}-north", name: "north", lat: 35.6836, lng: 139.77),
            google_place(id: "#{category}-south", name: "south", lat: 35.6764, lng: 139.77)
          ]
        }.to_json)
    end

    stub_request(:get, MAPBOX_REVERSE_GEOCODE)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "features" => [{ "properties" => { "name" => "Meguro" } }] }.to_json)

    stub_request(:get, MAPBOX_DIRECTIONS)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "code" => "Ok",
        "routes" => [{ "distance" => distance, "duration" => duration,
                       "geometry" => "_p~iF~ps|U_ulLnnqC_mqNvxq`@", "legs" => [{ "steps" => [] }] }]
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
