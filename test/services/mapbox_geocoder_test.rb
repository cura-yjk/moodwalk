require "test_helper"

# The neighbourhood label on every route card and walk card. It is cosmetic --
# callers fall back to "Nearby" -- which is exactly why it is worth testing:
# a broken geocoder looks identical to a point that genuinely has no name.
class MapboxGeocoderTest < ActiveSupport::TestCase
  LAT = 35.68
  LNG = 139.77

  test "returns the short neighbourhood name" do
    stub_reverse(features: [feature(name: "Meguro", place_formatted: "Meguro, Tokyo")])

    assert_equal "Meguro", MapboxGeocoder.reverse(LAT, LNG)
  end

  test "asks for the point it was given, at neighbourhood level" do
    stub_reverse(features: [feature(name: "Meguro")])

    MapboxGeocoder.reverse(LAT, LNG)

    assert_requested :get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse} do |request|
      query = request.uri.query_values
      query["latitude"].to_f == LAT && query["longitude"].to_f == LNG &&
        query["types"] == "neighborhood,locality,place"
    end
  end

  # Mapbox's most specific match is sometimes a block or chome number rather
  # than a place name -- "2" is not a neighbourhood anyone recognises.
  test "skips a bare number and takes the first real name" do
    stub_reverse(features: [feature(name: "2"), feature(name: "Nakameguro")])

    assert_equal "Nakameguro", MapboxGeocoder.reverse(LAT, LNG)
  end

  # Some tiers return a comma-joined composite rather than a short label, which
  # is too long for the card it goes on.
  test "skips a comma-joined composite and takes the first short name" do
    stub_reverse(features: [feature(name: "Meguro, Tokyo 153-0063"), feature(name: "Yutenji")])

    assert_equal "Yutenji", MapboxGeocoder.reverse(LAT, LNG)
  end

  test "falls back to the formatted place when no feature has a usable name" do
    stub_reverse(features: [feature(name: "4", place_formatted: "Shibuya, Tokyo")])

    assert_equal "Shibuya, Tokyo", MapboxGeocoder.reverse(LAT, LNG)
  end

  test "a point with no features has no name, rather than raising" do
    stub_reverse(features: [])

    assert_nil MapboxGeocoder.reverse(LAT, LNG)
  end

  # Non-fatal by design: the callers show "Nearby" instead. The walk must not
  # fail because its label could not be looked up.
  test "an upstream failure is survivable and logged, not raised" do
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse}).to_timeout

    logged = capture_warnings { assert_nil MapboxGeocoder.reverse(LAT, LNG) }

    assert_match "MapboxGeocoder.reverse failed", logged,
                 "a geocoder that is timing out must not look like a place with no name"
  end

  test "an unreadable response is survivable too" do
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 502, body: "<html>Bad Gateway</html>")

    name = nil
    logged = capture_warnings { name = MapboxGeocoder.reverse(LAT, LNG) }

    assert_nil name
    assert_match "MapboxGeocoder.reverse failed", logged
  end

  private

  def stub_reverse(features:)
    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "features" => features }.to_json)
  end

  def feature(name:, place_formatted: nil)
    { "properties" => { "name" => name, "place_formatted" => place_formatted }.compact }
  end

  def capture_warnings
    original = Rails.logger
    captured = StringIO.new
    Rails.logger = Logger.new(captured)
    yield
    captured.string
  ensure
    Rails.logger = original
  end
end
