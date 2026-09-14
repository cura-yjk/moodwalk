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

  def stub_forward_geocode_empty
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward})
      .to_return(status: 200, body: { "features" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end
end
