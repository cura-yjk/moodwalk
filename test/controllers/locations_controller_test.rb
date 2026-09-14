require "test_helper"

class LocationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:walker) }

  test "requires authentication" do
    sign_out users(:walker)
    patch location_path, params: { latitude: 35.68, longitude: 139.77 }

    assert_redirected_to new_user_session_path
  end

  test "stores coordinates from the browser and names them" do
    stub_reverse_geocode("Nakameguro")

    patch location_path, params: { latitude: 35.6446, longitude: 139.6994 }

    assert_response :success
    user = users(:walker).reload
    assert_in_delta 35.6446, user.current_latitude, 0.0001
    assert_equal "Nakameguro", user.current_location_name
  end

  # Junk coordinates used to be written straight to the user record, from where
  # they flow into Journey.near and RouteBuilder.
  test "rejects coordinates that are not numbers" do
    before = users(:walker).current_latitude

    patch location_path, params: { latitude: "not-a-number", longitude: "also-not" }

    assert_response :unprocessable_entity
    assert_equal before, users(:walker).reload.current_latitude
  end

  test "manual entry geocodes a typed place name" do
    stub_forward_geocode("Yutenji", lat: 35.6531, lng: 139.6858)

    patch location_path, params: { query: "Yutenji" }

    assert_response :success
    user = users(:walker).reload
    assert_equal "Yutenji", user.current_location_name
    assert_in_delta 35.6531, user.current_latitude, 0.0001
  end

  test "manual entry reports an unfindable place without changing anything" do
    stub_forward_geocode_empty
    before = users(:walker).current_location_name

    patch location_path, params: { query: "asdfghjkl" }

    assert_response :unprocessable_entity
    assert_match(/couldn't find that place/i, response.parsed_body["error"])
    assert_equal before, users(:walker).reload.current_location_name
  end

  # Without a proximity bias the search is global, and a near-miss resolves to
  # a fuzzy match on the other side of the country.
  test "manual entry biases the search toward the user's current location" do
    users(:walker).update!(current_latitude: 35.6446, current_longitude: 139.6994)
    stub_forward_geocode("Yutenji", lat: 35.6531, lng: 139.6858)

    patch location_path, params: { query: "Yutenji" }

    assert_requested :get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward},
                     query: hash_including("proximity" => "139.6994,35.6446")
  end

  test "manual entry still works for a user with no location yet" do
    users(:walker).update!(current_latitude: nil, current_longitude: nil)
    stub_forward_geocode("Yutenji", lat: 35.6531, lng: 139.6858)

    patch location_path, params: { query: "Yutenji" }

    assert_response :success
    assert_equal "Yutenji", users(:walker).reload.current_location_name
  end

  # Mapbox answers almost any input; a guessed address match is flagged
  # "low" confidence, and taking it would silently move the user continents.
  test "manual entry refuses a low-confidence guess" do
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "features" => [{
          "properties" => { "name" => "Place Lesseps 123", "match_code" => { "confidence" => "low" } },
          "geometry" => { "coordinates" => [2.149961, 41.406132] }
        }]
      }.to_json)
    before = users(:walker).current_latitude

    patch location_path, params: { query: "zzzqqqxxx not a place" }

    assert_response :unprocessable_entity
    assert_equal before, users(:walker).reload.current_latitude
  end

  test "manual entry rejects a blank query" do
    patch location_path, params: { query: "   " }

    assert_response :unprocessable_entity
  end

  # The rescue used to echo the exception straight to the client.
  test "an upstream failure does not leak provider detail" do
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .to_return(status: 500, body: "<html>Mapbox internal error, token sk-secret</html>")

    patch location_path, params: { query: "Anywhere" }

    assert_response :unprocessable_entity
    assert_no_match(/mapbox|sk-secret|html/i, response.body)
  end

  # --- typeahead ------------------------------------------------------------

  test "autocomplete returns named places with the district they sit in" do
    stub_forward_geocode("Yutenji", lat: 35.6531, lng: 139.6858)

    get autocomplete_location_path, params: { query: "Yute" }

    assert_response :success
    result = response.parsed_body["results"].first
    assert_equal "Yutenji", result["name"]
    # The context line is what lets a user reject a wrong match before applying it.
    assert_equal "Yutenji, Tokyo", result["place_formatted"]
  end

  test "autocomplete returns nothing for a blank query without calling Mapbox" do
    get autocomplete_location_path, params: { query: "  " }

    assert_response :success
    assert_empty response.parsed_body["results"]
    assert_not_requested :get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward}
  end

  # A picked suggestion carries its own name, so there is no second geocode.
  test "choosing a suggestion stores it without re-geocoding" do
    patch location_path, params: { latitude: 35.6531, longitude: 139.6858, name: "Yutenji" }

    assert_response :success
    assert_equal "Yutenji", users(:walker).reload.current_location_name
    assert_not_requested :get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse}
  end

  # Mapbox treats proximity as a hard filter, not a soft bias: "Paris" with
  # proximity set to Tokyo returns nothing at all. Without the global retry,
  # you could never set a location in another city.
  test "autocomplete falls back to a global search when nothing nearby matches" do
    users(:walker).update!(current_latitude: 35.6446, current_longitude: 139.6994)
    stub_forward_geocode_empty_for_proximity
    stub_forward_geocode_global("Paris", lat: 48.8566, lng: 2.3522)

    get autocomplete_location_path, params: { query: "Paris" }

    assert_response :success
    assert_equal "Paris", response.parsed_body["results"].first["name"]
  end

  test "a nearby match is returned without a second global search" do
    users(:walker).update!(current_latitude: 35.6446, current_longitude: 139.6994)
    stub_forward_geocode("Yutenji", lat: 35.6531, lng: 139.6858)

    get autocomplete_location_path, params: { query: "Yutenji" }

    assert_response :success
    # One request only: the local search answered, so no global retry.
    assert_requested :get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward}, times: 1
  end

  test "a user with no location searches globally in one request" do
    users(:walker).update!(current_latitude: nil, current_longitude: nil)
    stub_forward_geocode("Paris", lat: 48.8566, lng: 2.3522)

    get autocomplete_location_path, params: { query: "Paris" }

    assert_response :success
    assert_requested :get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward}, times: 1
  end

  # --- a chosen place stays chosen ------------------------------------------

  # Reported: "I changed the location and then after generating a walk, my
  # location was set back to my current location." Detection could not tell a
  # deliberate choice from a stale fix, so it corrected it away on the next
  # page load.
  test "a background sync does not move a pinned location" do
    patch location_path, params: { latitude: 35.6580, longitude: 139.7016, name: "Shibuya", source: "manual" }
    assert users(:walker).reload.location_manually_set

    patch location_path, params: { latitude: 35.6640, longitude: 139.8740 }

    assert_response :no_content
    assert_equal "Shibuya", users(:walker).reload.current_location_name
  end

  test "typing a place name pins it too" do
    stub_forward_geocode("Yutenji", lat: 35.6531, lng: 139.6858)

    patch location_path, params: { query: "Yutenji" }

    assert users(:walker).reload.location_manually_set
  end

  # "Use my current location" is an explicit request, so unlike the background
  # sync it may move a pinned location -- that is how tracking resumes.
  test "using current location unpins and moves" do
    patch location_path, params: { latitude: 35.6580, longitude: 139.7016, name: "Shibuya", source: "manual" }
    stub_reverse_geocode("Kasai")

    patch location_path, params: { latitude: 35.6640, longitude: 139.8740, source: "detect" }

    assert_response :success
    user = users(:walker).reload
    assert_equal "Kasai", user.current_location_name
    assert_not user.location_manually_set
  end

  test "a background sync moves an unpinned location as before" do
    users(:walker).update!(location_manually_set: false)
    stub_reverse_geocode("Kasai")

    patch location_path, params: { latitude: 35.6640, longitude: 139.8740 }

    assert_response :success
    assert_equal "Kasai", users(:walker).reload.current_location_name
  end

  # --- recent locations -----------------------------------------------------

  test "moving somewhere remembers where you were" do
    users(:walker).update!(current_latitude: 35.6446, current_longitude: 139.6994,
                           current_location_name: "Nakameguro", recent_locations: [])

    patch location_path, params: { latitude: 35.6531, longitude: 139.6858, name: "Yutenji" }

    recents = users(:walker).reload.recent_locations_list
    assert_equal ["Nakameguro"], recents.map { |r| r[:name] }
  end

  test "recent locations are capped and most-recent-first" do
    user = users(:walker)
    user.update!(recent_locations: [])

    user.update!(current_location_name: nil, current_latitude: nil, current_longitude: nil)

    %w[A B C D E F].each_with_index do |name, i|
      user.move_to!(latitude: 35.60 + (i * 0.05), longitude: 139.60 + (i * 0.05), name: name)
    end

    names = user.reload.recent_locations_list.map { |r| r[:name] }
    assert_equal User::MAX_RECENT_LOCATIONS, names.size
    assert_equal %w[E D C B], names
  end

  test "returning to the same place does not duplicate it in recents" do
    user = users(:walker)
    # Start from nowhere, so the fixture's own location isn't also remembered.
    user.update!(recent_locations: [], current_location_name: nil,
                 current_latitude: nil, current_longitude: nil)

    user.move_to!(latitude: 35.6446, longitude: 139.6994, name: "Nakameguro")
    user.move_to!(latitude: 35.6531, longitude: 139.6858, name: "Yutenji")
    user.move_to!(latitude: 35.6446, longitude: 139.6994, name: "Nakameguro")

    assert_equal %w[Yutenji Nakameguro], user.reload.recent_locations_list.map { |r| r[:name] }
  end

  private

  def stub_reverse_geocode(name)
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "features" => [{ "properties" => { "name" => name } }] }.to_json)
  end

  def stub_forward_geocode(name, lat:, lng:)
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "features" => [{
          "properties" => { "name" => name, "place_formatted" => "#{name}, Tokyo" },
          "geometry" => { "coordinates" => [lng, lat] }
        }]
      }.to_json)
  end

  # Empty when proximity is sent (Mapbox filtering distant results out)...
  def stub_forward_geocode_empty_for_proximity
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .with(query: hash_including("proximity"))
      .to_return(status: 200, body: { "features" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # ...and answering once the retry drops it.
  def stub_forward_geocode_global(name, lat:, lng:)
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .with { |req| !req.uri.query.to_s.include?("proximity") }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "features" => [{
          "properties" => { "name" => name, "place_formatted" => "#{name}, France" },
          "geometry" => { "coordinates" => [lng, lat] }
        }]
      }.to_json)
  end

  def stub_forward_geocode_empty
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .to_return(status: 200, body: { "features" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end
end
