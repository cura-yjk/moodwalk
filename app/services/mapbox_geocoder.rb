# app/services/mapbox_geocoder.rb
class MapboxGeocoder
  REVERSE_GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/reverse"

  # Neighborhood/district-level label for a point (e.g. "Meguro"), not a
  # street address -- same Mapbox v6 endpoint/types LocationsController uses
  # for the "starting from" label.
  def self.reverse(latitude, longitude)
    features = fetch_features(latitude, longitude)
    clean_name(features) || features.first&.dig("properties", "place_formatted")
  rescue StandardError => e
    # A missing label is cosmetic (callers fall back to "Nearby"), so this
    # stays non-fatal -- but log it, or a timing out/misconfigured geocoder
    # looks identical to a point that genuinely has no name.
    Rails.logger.warn("MapboxGeocoder.reverse failed: #{e.class}: #{e.message}")
    nil
  end

  def self.fetch_features(latitude, longitude)
    response = ExternalApi.connection.get(REVERSE_GEOCODE_URL) do |req|
      req.params["longitude"] = longitude
      req.params["latitude"] = latitude
      req.params["language"] = "en"
      req.params["types"] = "neighborhood,locality,place"
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    ExternalApi.parse_json(response, service: "Mapbox Geocoding")["features"].to_a
  end
  private_class_method :fetch_features

  # Mapbox's most specific match is sometimes just a block/chome number (e.g.
  # "2" in Japanese addressing) rather than a real place name, and some tiers'
  # "name" is a comma-joined composite (e.g. "Meguro, Tokyo 153-0063") rather
  # than a short label -- skip those and take the first feature with a plain
  # short name instead.
  def self.clean_name(features)
    features.each do |feature|
      name = feature.dig("properties", "name")
      return name if name.present? && !name.match?(/\A\d+\z/) && !name.include?(",")
    end
    nil
  end
  private_class_method :clean_name
end
