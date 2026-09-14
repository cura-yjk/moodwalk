class LocationsController < ApplicationController
  GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward"

  # Mapbox returns *something* for almost any input: "zzzqqqxxx not a place
  # 123" comes back as an address in Barcelona. Guessed address matches carry a
  # match_code whose confidence is "low"; genuine place/neighborhood matches
  # carry no match_code at all. Dropping the low-confidence ones is what stops
  # a typo silently relocating someone to another continent.
  LOW_CONFIDENCE = "low"

  # Two ways in, both used by the location bar (shared/_location_bar):
  # coordinates from the browser's Geolocation API, or a place name typed by
  # hand when detection is blocked or wrong.
  def update
    if coordinates_given?
      update_from_coordinates(latitude_param, longitude_param)
    else
      update_from_query(params[:query].to_s.strip)
    end
  rescue StandardError => e
    # The message is for the log, not the client: it can carry provider and
    # internal detail, and there is nothing the user could do with it.
    Rails.logger.error("LocationsController#update failed: #{e.class}: #{e.message}")
    render json: { error: "Couldn't update your location just now." }, status: :unprocessable_entity
  end

  private

  # Rejects anything that isn't a real coordinate rather than writing junk to
  # the user record, which then flows into Journey.near and RouteBuilder.
  def coordinates_given?
    latitude_param && longitude_param
  end

  def latitude_param
    @latitude_param ||= Float(params[:latitude], exception: false)&.clamp(-90.0, 90.0)
  end

  def longitude_param
    @longitude_param ||= Float(params[:longitude], exception: false)&.clamp(-180.0, 180.0)
  end

  def update_from_coordinates(latitude, longitude, name = nil)
    name ||= MapboxGeocoder.reverse(latitude, longitude)

    current_user.update!(
      current_latitude: latitude,
      current_longitude: longitude,
      current_location_name: name
    )
    head :ok
  end

  def update_from_query(query)
    return not_found("Enter a town, district or landmark.") if query.blank?

    result = geocode(query)
    return not_found("Couldn't find that place. Try a nearby landmark or district.") unless result

    current_user.update!(
      current_latitude: result[:lat],
      current_longitude: result[:lng],
      current_location_name: result[:name]
    )
    render json: { latitude: result[:lat], longitude: result[:lng], name: result[:name] }, status: :ok
  end

  def not_found(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def suggest(query, limit: 5)
    return [] if query.blank?

    response = geocode_request(query, limit)

    ExternalApi.parse_json(response, service: "Mapbox Geocoding")["features"]
               .to_a.select { |feature| confident_match?(feature) }
               .map { |feature| feature_to_suggestion(feature) }
  end

  def geocode_request(query, limit)
    ExternalApi.connection.get(GEOCODE_URL) do |req|
      req.params["q"] = query
      req.params["autocomplete"] = true
      req.params["limit"] = limit
      req.params["language"] = "en"
      # Bias toward where the user already is. Without this the search is
      # global and lands on fuzzy far-away matches -- a near-miss resolved to a
      # same-sounding place 600km away.
      req.params["proximity"] = proximity if proximity
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end
  end

  # Mapbox wants "longitude,latitude".
  def proximity
    return nil unless current_user.current_longitude && current_user.current_latitude

    "#{current_user.current_longitude},#{current_user.current_latitude}"
  end

  def confident_match?(feature)
    feature.dig("properties", "match_code", "confidence") != LOW_CONFIDENCE
  end

  # Mapbox returns coordinates as [longitude, latitude] -- easy to mix up.
  def feature_to_suggestion(feature)
    lng, lat = feature.dig("geometry", "coordinates")
    {
      name: feature.dig("properties", "name") || feature.dig("properties", "place_formatted"),
      place_formatted: feature.dig("properties", "place_formatted"),
      lat: lat,
      lng: lng
    }
  end

  def geocode(query)
    suggest(query, limit: 1).first
  end
end
