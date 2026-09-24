require "test_helper"

class PoiFinderTest < ActiveSupport::TestCase
  LAT = 35.68
  LNG = 139.77

  test "returns POIs shaped for downstream consumers, with correct distance" do
    stub_nearby_search("park", places: [google_place(id: "place-1", name: "Test Park", lat: 35.6817966, lng: 139.77)])

    result = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

    assert result.success?
    assert_equal 1, result.pois.size

    poi = result.pois.first
    assert_equal "place-1", poi[:id]
    assert_equal "Test Park", poi[:name]
    assert_equal "park", poi[:category]
    assert_in_delta 200, poi[:distance_meters], 5
  end

  test "makes one request per category and dedupes shared results" do
    stub_nearby_search("park", places: [google_place(id: "shared-1", name: "Shared", lat: LAT, lng: LNG)])
    stub_nearby_search("bakery", places: [
                         google_place(id: "shared-1", name: "Shared", lat: LAT, lng: LNG),
                         google_place(id: "bakery-1", name: "Bread", lat: LAT, lng: LNG)
                       ])

    result = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park", "bakery"]).call

    assert result.success?
    assert_equal(["shared-1", "bakery-1"], result.pois.map { |poi| poi[:id] })
    assert_equal(["park", "bakery"], result.pois.map { |poi| poi[:category] })
  end

  test "treats an empty places list as zero results, not an error" do
    stub_nearby_search("park", body: {}.to_json)

    result = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

    assert result.success?
    assert_empty result.pois
  end

  test "surfaces a Google error response as a failure" do
    stub_nearby_search("park", body: { "error" => { "message" => "API key not valid" } }.to_json)

    result = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

    assert_not result.success?
    assert_match(/API key not valid/, result.error)
  end

  test "sends the expected auth header, field mask, and request body" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .with(
        headers: { "X-Goog-FieldMask" => PoiFinder::FIELD_MASK, "Content-Type" => "application/json" },
        body: hash_including(
          "includedPrimaryTypes" => ["park"],
          "languageCode" => "en",
          "locationRestriction" => { "circle" => { "center" => { "latitude" => LAT, "longitude" => LNG },
                                                   "radius" => 1500 } }
        )
      )
      .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    result = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

    assert result.success?
  end

  # includedTypes matches any type a place carries, and Google tags liberally:
  # measured in Tokyo, a bar came back as a hiking_area, a massage shop and a
  # vehicle dispatch office as campgrounds, an association office as a
  # marina. A place's primary type is what it actually is.
  test "matches places on what they primarily are, not on any tag they carry" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    PoiFinder.new(lat: LAT, lng: LNG, categories: ["hiking_area"]).call

    assert_requested(:post, PoiFinder::NEARBY_SEARCH_URL) do |request|
      body = JSON.parse(request.body)
      body["includedPrimaryTypes"] == ["hiking_area"] && !body.key?("includedTypes")
    end
  end

  # --- enough_nearby? -------------------------------------------------------

  test "asks about a whole theme in one request" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .with(body: hash_including("includedPrimaryTypes" => %w[park garden]))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "places" => [place_json("a"), place_json("b")] }.to_json)

    assert PoiFinder.new(lat: LAT, lng: LNG, categories: %w[park garden]).enough_nearby?(2)
    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: 1
  end

  test "too few places within reach is not enough" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "places" => [place_json("a")] }.to_json)

    assert_not PoiFinder.new(lat: LAT, lng: LNG, categories: %w[park garden]).enough_nearby?(2)
  end

  test "a failed request counts as not enough rather than raising" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL).to_return(status: 500)

    assert_not PoiFinder.new(lat: LAT, lng: LNG, categories: %w[park]).enough_nearby?(2)
  end

  # --- caching -----------------------------------------------------------
  #
  # One generated route costs one Google request per theme category, and
  # RouteBuilder retries, so a cheerful route measured at 24 of them. The same
  # ground gets searched over and over: a user turning down a walk and asking
  # again, two people leaving the same station, the retry loop itself.

  test "a repeated search is served from the cache instead of Google" do
    with_memory_cache do
      stub_nearby_search("park", places: [google_place(id: "p1", name: "Park", lat: LAT, lng: LNG)])

      3.times { PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call }

      assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: 1
    end
  end

  test "two walkers a few doors apart share one search, each with their own distances" do
    with_memory_cache do
      stub_nearby_search("park", places: [google_place(id: "p1", name: "Park", lat: 35.6817966, lng: 139.77)])

      here = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call
      # ~55m south: inside the same cache cell, so no second request -- but the
      # walk from their door is a different length and must say so.
      there = PoiFinder.new(lat: LAT - 0.0005, lng: LNG, categories: ["park"]).call

      assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: 1
      assert_operator there.pois.first[:distance_meters], :>, here.pois.first[:distance_meters],
                      "the second walker was handed the first one's distances"
    end
  end

  test "a different radius is a different search" do
    with_memory_cache do
      stub_nearby_search("park", places: [google_place(id: "p1", name: "Park", lat: LAT, lng: LNG)])

      PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"], radius_meters: 800).call
      PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"], radius_meters: 1600).call

      assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: 2
    end
  end

  test "a failed search is not remembered as an answer" do
    with_memory_cache do
      stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { "error" => { "message" => "quota" } }.to_json).then
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { "places" => [google_place(id: "p1", name: "Park", lat: LAT, lng: LNG)] }.to_json)

      failed = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call
      recovered = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

      assert_not failed.success?
      assert recovered.success?, "the failure was cached, so the next search never reached Google"
      assert_equal 1, recovered.pois.size
    end
  end

  test "asks Google for as many results as it will give, since the price is the same either way" do
    stub_nearby_search("park", places: [])

    PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL do |request|
      JSON.parse(request.body)["maxResultCount"] == 20
    end
  end

  private

  # The test environment runs on :null_store, which never returns anything it
  # was given -- so without a real store here every cache test would pass by
  # doing nothing.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end


  def google_place(id:, name:, lat:, lng:)
    { "id" => id, "displayName" => { "text" => name }, "location" => { "latitude" => lat, "longitude" => lng } }
  end

  def stub_nearby_search(category, places: nil, body: nil)
    response_body = body || { "places" => places }.to_json
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .with(body: hash_including("includedPrimaryTypes" => [category]))
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
  end

  def place_json(id)
    { "id" => id, "displayName" => { "text" => id }, "location" => { "latitude" => LAT, "longitude" => LNG } }
  end
end
