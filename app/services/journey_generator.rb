# app/services/journey_generator.rb
class JourneyGenerator
  MAPBOX_DIRECTIONS_URL = "https://api.mapbox.com/directions/v5/mapbox/walking"
  MAX_ATTEMPTS = 3
  TOLERANCE_RATIO = 0.15

  # A u-turn right at a real waypoint is expected (a spur out to a POI down a
  # dead-end path naturally turns back there); this allows for Mapbox snapping
  # the route to the nearest road rather than the exact POI coordinate.
  WAYPOINT_PROXIMITY_TOLERANCE_METERS = 30

  Result = Struct.new(:success?, :journey, :error, keyword_init: true)

  def initialize(lat:, lng:, target_distance_meters: nil, waypoints: nil, description: nil,
                 theme_key: nil, name: nil, round_trip: nil, base_bearing: nil)
    @lat = lat.to_f
    @lng = lng.to_f
    @target_distance = target_distance_meters&.to_f
    @waypoints = waypoints
    @description = description
    @theme_key = theme_key
    @name = name
    @round_trip = round_trip.nil? ? [true, false].sample : round_trip
    @base_bearing = base_bearing
  end

  def call
    if @waypoints.present?
      call_with_real_waypoints
    else
      call_with_synthetic_loop
    end
  end

  private

  def call_with_real_waypoints
    directions = fetch_directions(@waypoints)
    return Result.new(success?: false, error: directions[:error]) if directions[:error]

    Result.new(success?: true, journey: build_journey(directions))
  end

  def call_with_synthetic_loop
    return missing_target_result if @target_distance.blank?

    radius = @round_trip ? @target_distance / (2 * Math::PI) : @target_distance

    MAX_ATTEMPTS.times do |attempt|
      directions = fetch_directions(synthetic_waypoints(radius))
      return Result.new(success?: false, error: directions[:error]) if directions[:error]

      ratio = directions[:distance] / @target_distance
      return Result.new(success?: true, journey: build_journey(directions)) if close_enough?(ratio, attempt)

      radius *= (1 / ratio)
    end

    # Unreachable while the last attempt always returns, but an explicit
    # failure beats leaking `MAX_ATTEMPTS.times`'s integer to a caller that
    # immediately asks it for #success?.
    Result.new(success?: false, error: "Could not reach the target distance")
  end

  def missing_target_result
    Result.new(success?: false, error: "target_distance_meters is required when no waypoints are given")
  end

  def close_enough?(ratio, attempt)
    (ratio - 1).abs <= TOLERANCE_RATIO || attempt == MAX_ATTEMPTS - 1
  end

  def synthetic_waypoints(radius)
    @round_trip ? build_loop_waypoints(radius) : build_oneway_waypoints(radius)
  end

  def build_oneway_waypoints(distance)
    bearing = @base_bearing ? @base_bearing + rand(-20..20) : rand(0..359)
    [GeoDistance.destination_point(@lat, @lng, distance, bearing)]
  end

  # Same evenly-spaced square as the unbiased case, just rotated toward base_bearing when given.
  def build_loop_waypoints(radius)
    bearings = [0, 90, 180, 270].map { |b| b + (@base_bearing || 0) + rand(-20..20) }
    bearings.map { |bearing| GeoDistance.destination_point(@lat, @lng, radius, bearing) }
  end

  def fetch_directions(waypoints)
    points = [{ lat: @lat, lng: @lng }] + waypoints
    points += [{ lat: @lat, lng: @lng }] if @round_trip

    body = request_directions(points)
    return { error: body["message"] || "No route found" } if body["code"] != "Ok" || body["routes"].blank?

    route = body["routes"].first
    return { error: "route backtracks on itself (dead end / u-turn)" } if themed_dead_end?(route)

    { distance: route["distance"], duration: route["duration"], polyline: route["geometry"] }
  end

  def request_directions(points)
    coords = points.map { |p| "#{p[:lng]},#{p[:lat]}" }.join(";")

    response = ExternalApi.connection.get("#{MAPBOX_DIRECTIONS_URL}/#{coords}") do |req|
      req.params["geometries"] = "polyline"
      req.params["overview"] = "full"
      req.params["steps"] = "true" if @theme_key # only themed routes get the dead-end check
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    ExternalApi.parse_json(response, service: "Mapbox Directions")
  end

  # A u-turn away from any real waypoint means retracing the same path for no
  # reason (dead end) - but a u-turn right at a waypoint is expected (see the
  # tolerance constant above). Only checked for themed routes.
  def themed_dead_end?(route)
    return false unless @theme_key

    route["legs"].flat_map { |l| l["steps"] }.any? do |step|
      step.dig("maneuver", "modifier") == "uturn" && !near_waypoint?(step)
    end
  end

  def near_waypoint?(step)
    location = step.dig("maneuver", "location")
    return false unless location

    step_lng, step_lat = location
    Array(@waypoints).any? do |wp|
      GeoDistance.haversine(step_lat, step_lng, wp[:lat], wp[:lng]) <= WAYPOINT_PROXIMITY_TOLERANCE_METERS
    end
  end

  def build_journey(directions)
    Journey.new(route_attrs(directions).merge(descriptive_attrs))
  end

  def route_attrs(directions)
    {
      encoded_polyline: directions[:polyline],
      distance_meters: directions[:distance],
      estimated_duration_seconds: directions[:duration],
      estimated_steps: (directions[:distance] / Walk::STEP_LENGTH_METERS).round,
      start_point: start_point
    }
  end

  def descriptive_attrs
    {
      description: @description,
      theme_key: @theme_key,
      name: @name,
      location_name: MapboxGeocoder.reverse(@lat, @lng)
    }
  end

  def start_point
    RGeo::Geographic.spherical_factory(srid: 4326).point(@lng, @lat)
  end
end
