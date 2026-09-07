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
end
