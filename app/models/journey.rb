class Journey < ApplicationRecord
  has_many :walks

  scope :community, -> { joins(:walks).merge(Walk.shared).distinct }

  def community_photos(limit: nil)
    scope = walks.recent_with_photo
    limit ? scope.limit(limit) : scope
  end

  def estimated_steps_display
    estimated_steps || "—"
  end

  def placeholder_rating
    (3.8 + ((id % 5) * 0.2)).round(1)
  end

  def alternate
    others = Journey.where.not(id: id)
    others = others.where(estimated_duration_seconds: ..estimated_duration_seconds) if estimated_duration_seconds

    others.where(theme_key: theme_key).sample || others.sample
  end

  # find routes within `radius_meters` of a point, closest first
  scope :near, lambda { |lat, lng, radius_meters = 3000|
    point = RGeo::Geographic.spherical_factory(srid: 4326).point(lng, lat)
    where("ST_DWithin(start_point, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)", lng, lat, radius_meters)
      .order(Arel.sql("start_point <-> ST_SetSRID(ST_MakePoint(#{lng}, #{lat}), 4326)::geography"))
  }

  # Placeholder images
  PLACEHOLDER_IMAGES = [
    "https://images.unsplash.com/photo-1783394422782-2e8d9c80dc5e?q=80&w=1752&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
    "https://images.unsplash.com/photo-1519331379826-f10be5486c6f?q=80&w=1740&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
    "https://thumbs.dreamstime.com/b/quiet-street-small-american-town-42895985.jpg"
  ]

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

  # Whether the route returns to (roughly) where it started, vs. ending somewhere else
  # (one-way). Compares the decoded route's first/last points rather than any stored flag,
  # since round_trip isn't persisted -- a small tolerance absorbs Mapbox's start/end snapping
  # to the nearest walkable path (a few meters), well under the length of any real one-way leg.
  def loop?
    start_lng, start_lat = route_coordinates.first
    end_lng, end_lat = route_coordinates.last
    (start_lng - end_lng).abs < 0.0005 && (start_lat - end_lat).abs < 0.0005
  end

  def turn_waypoints(angle_threshold: 30)
    coords = route_coordinates # each pair is [lng, lat]
    return [] if coords.size < 3

    waypoints = [{ lat: coords[0][1], lng: coords[0][0], instruction: "start" }]

    coords.each_cons(3) do |a, b, c|
      delta = angle_delta(bearing(a, b), bearing(b, c))
      next if delta.abs < angle_threshold

      waypoints << { lat: b[1], lng: b[0], instruction: delta.positive? ? "right" : "left" }
    end

    waypoints << { lat: coords.last[1], lng: coords.last[0], instruction: "end" }
    waypoints
  end

  TEXT_TAG_KEYWORDS = {
    "Nature" => /tree|leaf|leaves|branch|garden|grass|greenery|forest|park/i,
    "Water" => /water|stream|river|lake|pond|shore|waterfront/i,
    "Quiet" => /quiet|hushed|still|calm|silence/i,
    "Historic" => /old|worn|weathered|stone|brick|landmark|monument/i,
    "Lively" => /market|bakery|bright|color|liveliness|delight/i
  }.freeze

  def tags
    return theme_tags if theme_key.present? && THEMES.key?(theme_key.to_sym)

    text_derived_tags
  end

  private

  def theme_tags
    THEMES.dig(theme_key.to_sym, :categories).to_a.map { |slug| slug.tr("_", " ").capitalize }
  end

  def text_derived_tags
    text = "#{name} #{description}"
    matched = TEXT_TAG_KEYWORDS.select { |_, pattern| text.match?(pattern) }.keys
    matched.presence || ["Walk"]
  end

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
  def bearing(from, to)
    lat1 = from[1] * Math::PI / 180
    lat2 = to[1] * Math::PI / 180
    dlng = (to[0] - from[0]) * Math::PI / 180
    y = Math.sin(dlng) * Math.cos(lat2)
    x = (Math.cos(lat1) * Math.sin(lat2)) - (Math.sin(lat1) * Math.cos(lat2) * Math.cos(dlng))
    ((Math.atan2(y, x) * 180 / Math::PI) + 360) % 360
  end

  def angle_delta(bearing_in, bearing_out)
    (((bearing_out - bearing_in) + 540) % 360) - 180 # normalized to -180..180
  end
end
