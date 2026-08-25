# app/services/journey_generator.rb
class JourneyGenerator
  MAPBOX_DIRECTIONS_URL = "https://api.mapbox.com/directions/v5/mapbox/walking"
  MAX_ATTEMPTS = 3
  TOLERANCE_RATIO = 0.15 # accept within 15% of target distance

  Result = Struct.new(:success?, :journey, :error, keyword_init: true)

  def initialize(lat:, lng:, target_distance_meters:)
    @lat = lat.to_f
    @lng = lng.to_f
    @target_distance = target_distance_meters.to_f
  end

  def call
    radius = @target_distance / (2 * Math::PI)

    MAX_ATTEMPTS.times do |attempt|
      waypoints = build_loop_waypoints(radius)
      directions = fetch_directions(waypoints)

      return Result.new(success?: false, error: directions[:error]) if directions[:error]

      actual_distance = directions[:distance]
      ratio = actual_distance / @target_distance

      if (ratio - 1).abs <= TOLERANCE_RATIO || attempt == MAX_ATTEMPTS - 1
        journey = save_journey(directions)
        return Result.new(success?: true, journey: journey)
      end

      # too short -> grow radius; too long -> shrink it
      radius *= (1 / ratio)
    end
  end

  private

  # Points around a rough circle at `radius` meters from origin, in bearing order,
  # so the walking directions API traces a loop rather than crisscrossing.
  def build_loop_waypoints(radius)
    bearings = [0, 90, 180, 270].map { |b| b + rand(-20..20) }

    bearings.map do |bearing|
      destination_point(@lat, @lng, radius, bearing)
    end
  end

  # Move `distance_meters` from (lat,lng) along `bearing_degrees`. Basic spherical destination formula.
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
    coords = ([{ lat: @lat, lng: @lng }] + waypoints + [{ lat: @lat, lng: @lng }])
             .map { |p| "#{p[:lng]},#{p[:lat]}" }
             .join(";")

    response = Faraday.get("#{MAPBOX_DIRECTIONS_URL}/#{coords}") do |req|
      req.params["geometries"] = "polyline"
      req.params["overview"] = "full"
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    body = JSON.parse(response.body)

    return { error: body["message"] || "No route found" } if body["code"] != "Ok" || body["routes"].blank?

    leg = body["routes"].first
    { distance: leg["distance"], duration: leg["duration"], polyline: leg["geometry"] }
  end

  def save_journey(directions)
    Journey.create!(
      encoded_polyline: directions[:polyline],
      distance_meters: directions[:distance],
      estimated_duration_seconds: directions[:duration],
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(@lng, @lat)
    )
  end
end
