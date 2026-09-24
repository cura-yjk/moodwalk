# Straight-line (great-circle) distance between two lat/lng points, in meters.
# Shared by PoiFinder (distance from search origin), PoiSelector (tour-distance
# scoring), and JourneyGenerator (waypoint-proximity check for the dead-end fix).
module GeoDistance
  EARTH_RADIUS_METERS = 6_378_137.0

  module_function

  def haversine(lat1, lng1, lat2, lng2)
    d_lat = (lat2 - lat1) * Math::PI / 180
    d_lng = (lng2 - lng1) * Math::PI / 180

    a = (Math.sin(d_lat / 2)**2) +
        (Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * (Math.sin(d_lng / 2)**2))

    2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(a))
  end

  # Initial great-circle bearing from one point to another, in compass degrees
  # (0 = north, clockwise). Shared by PoiSelector (how far apart a combination's
  # waypoints sit around the compass) and Journey#turn_waypoints (which way the
  # route turns at each vertex).
  def bearing(lat1, lng1, lat2, lng2)
    phi1 = lat1 * Math::PI / 180
    phi2 = lat2 * Math::PI / 180
    d_lng = (lng2 - lng1) * Math::PI / 180

    y = Math.sin(d_lng) * Math.cos(phi2)
    x = (Math.cos(phi1) * Math.sin(phi2)) - (Math.sin(phi1) * Math.cos(phi2) * Math.cos(d_lng))

    ((Math.atan2(y, x) * 180 / Math::PI) + 360) % 360
  end

  # The point you reach travelling `distance_meters` from (lat, lng) along a
  # constant compass bearing. The inverse of #bearing, and what JourneyGenerator
  # uses to plant synthetic waypoints around a circle.
  # rubocop:disable Metrics/MethodLength
  def destination_point(lat, lng, distance_meters, bearing_degrees)
    bearing = bearing_degrees * Math::PI / 180
    phi1 = lat * Math::PI / 180
    lambda1 = lng * Math::PI / 180
    angular = distance_meters / EARTH_RADIUS_METERS

    phi2 = Math.asin(
      (Math.sin(phi1) * Math.cos(angular)) + (Math.cos(phi1) * Math.sin(angular) * Math.cos(bearing))
    )
    lambda2 = lambda1 + Math.atan2(
      Math.sin(bearing) * Math.sin(angular) * Math.cos(phi1),
      Math.cos(angular) - (Math.sin(phi1) * Math.sin(phi2))
    )

    { lat: phi2 * 180 / Math::PI, lng: lambda2 * 180 / Math::PI }
  end
  # rubocop:enable Metrics/MethodLength

  # Metres [east, north] of an origin, on a flat projection - plenty at the
  # scale of a walk. For measuring area and nearness, which great-circle
  # distances alone can't do: PoiSelector's loop roundness and RouteOverlap's
  # grid.
  def local_offset(origin_lat, origin_lng, lat, lng)
    meters_per_degree = EARTH_RADIUS_METERS * Math::PI / 180
    east = (lng - origin_lng) * meters_per_degree * Math.cos(origin_lat * Math::PI / 180)
    north = (lat - origin_lat) * meters_per_degree

    [east, north]
  end
end
