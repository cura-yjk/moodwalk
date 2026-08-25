class Journey < ApplicationRecord
  has_many :walks

  # find routes within `radius_meters` of a point, closest first
  scope :near, lambda { |lat, lng, radius_meters = 3000|
    point = RGeo::Geographic.spherical_factory(srid: 4326).point(lng, lat)
    where("ST_DWithin(start_point, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)", lng, lat, radius_meters)
      .order(Arel.sql("start_point <-> ST_SetSRID(ST_MakePoint(#{lng}, #{lat}), 4326)::geography"))
  }

  # decodes `encoded_polyline` (Google/Mapbox encoded polyline, precision 5) into
  # [lng, lat] pairs, ready to drop into a GeoJSON LineString for Mapbox GL.
  # rubocop:disable Metrics/MethodLength
  def route_coordinates
    coordinates = []
    index = 0
    lat = 0
    lng = 0

    while index < encoded_polyline.length
      delta, index = decode_polyline_value(encoded_polyline, index)
      lat += delta
      delta, index = decode_polyline_value(encoded_polyline, index)
      lng += delta

      coordinates << [lng / 1e5, lat / 1e5]
    end

    coordinates
  end
  # rubocop:enable Metrics/MethodLength

  def start_coordinates
    [start_point.x, start_point.y]
  end

  private

  # decodes one zigzag-encoded varint starting at `index`, returning [value, next_index]
  # rubocop:disable Metrics/MethodLength
  def decode_polyline_value(encoded, index)
    shift = 0
    result = 0
    loop do
      byte = encoded[index].ord - 63
      index += 1
      result |= (byte & 0x1f) << shift
      shift += 5
      break if byte < 0x20
    end

    value = result.nobits?(1) ? (result >> 1) : ~(result >> 1)
    [value, index]
  end
  # rubocop:enable Metrics/MethodLength
end
