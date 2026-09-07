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
          "includedTypes" => ["park"],
          "languageCode" => "en",
          "locationRestriction" => { "circle" => { "center" => { "latitude" => LAT, "longitude" => LNG },
                                                   "radius" => 1500 } }
        )
      )
      .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    result = PoiFinder.new(lat: LAT, lng: LNG, categories: ["park"]).call

    assert result.success?
  end

  private

  def google_place(id:, name:, lat:, lng:)
    { "id" => id, "displayName" => { "text" => name }, "location" => { "latitude" => lat, "longitude" => lng } }
  end

  def stub_nearby_search(category, places: nil, body: nil)
    response_body = body || { "places" => places }.to_json
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .with(body: hash_including("includedTypes" => [category]))
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
  end
end
