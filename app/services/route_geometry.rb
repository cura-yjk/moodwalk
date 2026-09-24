# A route's shape, read off its encoded polyline.
#
# Lifted out of Journey: decoding, the loop check and the turn list are
# geometry, and need nothing from the record but the polyline. Journey
# delegates the same three methods, so callers and views are unchanged.
class RouteGeometry
  def initialize(encoded_polyline:)
    @encoded_polyline = encoded_polyline
  end

  # decodes `encoded_polyline` (Google/Mapbox encoded polyline, precision 5) into
  # [lng, lat] pairs, ready to drop into a GeoJSON LineString for Mapbox GL.
  # Memoized: decoding walks the string character by character, and loop? alone
  # asks for it twice.
  def route_coordinates
    @route_coordinates ||= PolylineDecoder.decode(@encoded_polyline)
  end

  # Whether the route returns to (roughly) where it started, vs. ending somewhere else
  # (one-way). Compares the decoded route's first/last points rather than any stored flag,
  # since round_trip isn't persisted -- a small tolerance absorbs Mapbox's start/end snapping
  # to the nearest walkable path (a few meters), well under the length of any real one-way leg.
  def loop?
    coords = route_coordinates
    start_lng, start_lat = coords.first
    end_lng, end_lat = coords.last
    (start_lng - end_lng).abs < 0.0005 && (start_lat - end_lat).abs < 0.0005
  end

  # Share of the route (0-1) that re-walks ground it already covered - see
  # RouteOverlap. Memoized: ShortlistRouter asks once to accept a route, once
  # to rank it and again to report it, and measuring a long route three times
  # over took a build from ~50ms to ~750ms.
  def overlap_ratio
    @overlap_ratio ||= RouteOverlap.ratio(route_coordinates)
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

  private

  # `from`/`to` are [lng, lat] pairs, the shape route_coordinates yields.
  def bearing(from, to)
    GeoDistance.bearing(from[1], from[0], to[1], to[0])
  end

  def angle_delta(bearing_in, bearing_out)
    (((bearing_out - bearing_in) + 540) % 360) - 180 # normalized to -180..180
  end
end
