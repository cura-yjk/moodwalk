# app/services/journey_generator.rb
class JourneyGenerator
  MAPBOX_DIRECTIONS_URL = "https://api.mapbox.com/directions/v5/mapbox/walking"
  MAX_ATTEMPTS = 3
  TOLERANCE_RATIO = 0.15

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
    if @target_distance.blank?
      return Result.new(success?: false, error: "target_distance_meters is required when no waypoints are given")
    end

    radius = @round_trip ? @target_distance / (2 * Math::PI) : @target_distance

    MAX_ATTEMPTS.times do |attempt|
      waypoints = @round_trip ? build_loop_waypoints(radius) : build_oneway_waypoints(radius)
      directions = fetch_directions(waypoints)

      return Result.new(success?: false, error: directions[:error]) if directions[:error]

      actual_distance = directions[:distance]
      ratio = actual_distance / @target_distance

      if (ratio - 1).abs <= TOLERANCE_RATIO || attempt == MAX_ATTEMPTS - 1
        return Result.new(success?: true, journey: build_journey(directions))
      end

      radius *= (1 / ratio)
    end
  end

  def build_oneway_waypoints(distance)
    bearing = @base_bearing ? @base_bearing + rand(-20..20) : rand(0..359)
    [destination_point(@lat, @lng, distance, bearing)]
  end

  # Same evenly-spaced square as the unbiased case, just rotated toward base_bearing when given.
  def build_loop_waypoints(radius)
    bearings = [0, 90, 180, 270].map { |b| b + (@base_bearing || 0) + rand(-20..20) }
    bearings.map { |bearing| destination_point(@lat, @lng, radius, bearing) }
  end

  def destination_point(lat, lng, distance_meters, bearing_degrees)
    earth_radius = 6_378_137.0
    bearing = bearing_degrees * Math::PI / 180
    lat1 = lat * Math::PI / 180
    lng1 = lng * Math::PI / 180

    lat2 = Math.asin(
      (Math.sin(lat1) * Math.cos(distance_meters / earth_radius)) +
      (Math.cos(lat1) * Math.sin(distance_meters / earth_radius) * Math.cos(bearing))
    )
    lng2 = lng1 + Math.atan2(
      Math.sin(bearing) * Math.sin(distance_meters / earth_radius) * Math.cos(lat1),
      Math.cos(distance_meters / earth_radius) - (Math.sin(lat1) * Math.sin(lat2))
    )

    { lat: lat2 * 180 / Math::PI, lng: lng2 * 180 / Math::PI }
  end

  def fetch_directions(waypoints)
    points = [{ lat: @lat, lng: @lng }] + waypoints
    points += [{ lat: @lat, lng: @lng }] if @round_trip

    coords = points.map { |p| "#{p[:lng]},#{p[:lat]}" }.join(";")

    response = Faraday.get("#{MAPBOX_DIRECTIONS_URL}/#{coords}") do |req|
      req.params["geometries"] = "polyline"
      req.params["overview"] = "full"
      req.params["steps"] = "true" if @theme_key # only themed routes get the dead-end check below
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    body = JSON.parse(response.body)
    return { error: body["message"] || "No route found" } if body["code"] != "Ok" || body["routes"].blank?

    route = body["routes"].first
    return { error: "route backtracks on itself (dead end / u-turn)" } if themed_dead_end?(route)

    { distance: route["distance"], duration: route["duration"], polyline: route["geometry"] }
  end

  # A u-turn means retracing the same path (dead end). Only checked for themed routes.
  def themed_dead_end?(route)
    @theme_key && route["legs"].flat_map { |l| l["steps"] }.any? { |s| s.dig("maneuver", "modifier") == "uturn" }
  end

  def build_journey(directions)
    Journey.new(
      encoded_polyline: directions[:polyline],
      distance_meters: directions[:distance],
      estimated_duration_seconds: directions[:duration],
      estimated_steps: (directions[:distance] / 0.75).round,
      description: @description,
      theme_key: @theme_key,
      name: @name,
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(@lng, @lat)
    )
  end
end
