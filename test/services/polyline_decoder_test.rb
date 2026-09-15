require "test_helper"

# Every route the app draws is this decoder's output: Journey#route_coordinates
# feeds the Mapbox GL line, the walk comparison map, and turn_waypoints.
#
# The anchor is Google's own documented sample polyline and the three points it
# is published as decoding to, so the expectations come from the specification
# rather than from a previous run of this code.
class PolylineDecoderTest < ActiveSupport::TestCase
  CANONICAL = "_p~iF~ps|U_ulLnnqC_mqNvxq`@".freeze
  CANONICAL_POINTS = [[38.5, -120.2], [40.7, -120.95], [43.252, -126.453]].freeze

  test "decodes the documented sample polyline to its documented points" do
    decoded = PolylineDecoder.decode(CANONICAL)

    assert_equal 3, decoded.size
    CANONICAL_POINTS.each_with_index do |(lat, lng), i|
      assert_in_delta lng, decoded[i][0], 1e-9, "longitude of point #{i}"
      assert_in_delta lat, decoded[i][1], 1e-9, "latitude of point #{i}"
    end
  end

  test "emits [lng, lat], the order GeoJSON wants, not [lat, lng]" do
    # The two are indistinguishable near the equator and catastrophic in Tokyo,
    # so it is worth asserting on a point where they cannot be confused: the
    # sample's first point is at latitude 38.5 and longitude -120.2, and only
    # one of those can be a longitude.
    lng, lat = PolylineDecoder.decode(CANONICAL).first

    assert_in_delta(-120.2, lng, 1e-9)
    assert_in_delta 38.5, lat, 1e-9
  end

  test "an absent polyline decodes to no coordinates rather than raising" do
    # Journey#encoded_polyline is nullable and every map view calls this.
    assert_equal [], PolylineDecoder.decode(nil)
    assert_equal [], PolylineDecoder.decode("")
    assert_equal [], PolylineDecoder.decode("   ")
  end

  test "decodes a single point" do
    assert_equal [[-120.2, 38.5]], PolylineDecoder.decode("_p~iF~ps|U")
  end

  test "keeps five decimal places, the precision the format carries" do
    # 0.00001 degrees is one unit at precision 5 -- the smallest step the
    # encoding can express, and the one a precision-6 decoder would get wrong
    # by a factor of ten.
    decoded = PolylineDecoder.decode(encode([[0.00001, 0.00002]]))

    assert_in_delta 0.00002, decoded.first[0], 1e-12
    assert_in_delta 0.00001, decoded.first[1], 1e-12
  end

  test "decodes negative deltas, which are zigzag-encoded differently" do
    points = [[35.68, 139.77], [35.67, 139.76], [35.69, 139.78]]

    assert_points points, PolylineDecoder.decode(encode(points))
  end

  test "decodes deltas long enough to span several encoded bytes" do
    # A five-bit chunk per byte: a jump of half a degree is 50_000 units and
    # needs four, which is where an off-by-one in the shift shows up.
    points = [[35.68, 139.77], [36.18, 140.27]]

    assert_points points, PolylineDecoder.decode(encode(points))
  end

  test "round-trips a route-shaped sequence of points" do
    points = (0..20).map { |i| [35.68 + (i * 0.0013), 139.77 - (i * 0.0009)] }

    assert_points points, PolylineDecoder.decode(encode(points))
  end

  test "round-trips points either side of the equator and the prime meridian" do
    points = [[0.0, 0.0], [-0.5, 0.5], [0.5, -0.5], [-1.25, -1.25]]

    assert_points points, PolylineDecoder.decode(encode(points))
  end

  test "next_value reports where the next value starts" do
    # decode leans on this to walk the string; a wrong index silently shifts
    # every later coordinate rather than raising.
    value, index = PolylineDecoder.next_value("_p~iF~ps|U", 0)

    assert_equal 3_850_000, value
    assert_equal 5, index
  end

  private

  def assert_points(expected, decoded)
    assert_equal expected.size, decoded.size, "decoded the wrong number of points"

    expected.each_with_index do |(lat, lng), i|
      assert_in_delta lng, decoded[i][0], 1e-9, "longitude of point #{i}"
      assert_in_delta lat, decoded[i][1], 1e-9, "latitude of point #{i}"
    end
  end

  # A minimal encoder, written from the published algorithm, so the tests above
  # can state the points they mean instead of a string of punctuation. It is
  # only trusted because the canonical sample above pins the decoder to the
  # specification independently of it.
  def encode(points)
    previous_lat = 0
    previous_lng = 0

    points.map do |lat, lng|
      lat_units = (lat * 1e5).round
      lng_units = (lng * 1e5).round
      chunk = encode_value(lat_units - previous_lat) + encode_value(lng_units - previous_lng)
      previous_lat = lat_units
      previous_lng = lng_units
      chunk
    end.join
  end

  def encode_value(value)
    zigzag = value.negative? ? ~(value << 1) : (value << 1)
    encoded = +""

    while zigzag >= 0x20
      encoded << ((0x20 | (zigzag & 0x1f)) + 63).chr
      zigzag >>= 5
    end

    encoded << (zigzag + 63).chr
  end
end
