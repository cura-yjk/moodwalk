# Decodes a Google/Mapbox encoded polyline (precision 5) into [lng, lat] pairs,
# ready to drop into a GeoJSON LineString for Mapbox GL.
#
# Lives outside Journey because it's pure string math with no dependency on the
# record -- see Journey#route_coordinates, which memoizes the result.
module PolylineDecoder
  PRECISION = 1e5

  module_function

  # rubocop:disable Metrics/MethodLength
  def decode(encoded)
    return [] if encoded.blank?

    coordinates = []
    index = 0
    lat = 0
    lng = 0

    while index < encoded.length
      d_lat, index = next_value(encoded, index)
      d_lng, index = next_value(encoded, index)
      lat += d_lat
      lng += d_lng

      coordinates << [lng / PRECISION, lat / PRECISION]
    end

    coordinates
  end
  # rubocop:enable Metrics/MethodLength

  # decodes one zigzag-encoded varint starting at `index`,
  # returning [value, next_index]
  def next_value(encoded, index)
    shift = 0
    result = 0

    loop do
      byte = encoded[index].ord - 63
      index += 1
      result |= (byte & 0x1f) << shift
      shift += 5
      break if byte < 0x20
    end

    [result.nobits?(1) ? (result >> 1) : ~(result >> 1), index]
  end
end
