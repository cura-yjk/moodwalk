class LocationsController < ApplicationController
  GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward"
  REVERSE_GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/reverse"

  def update
    if params[:latitude].present? && params[:longitude].present?
      update_from_coordinates(params[:latitude], params[:longitude], params[:name])
    else
      update_from_query(params[:query])
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Typeahead suggestions as the user types in the location search box.
  def autocomplete
    render json: { results: suggest(params[:query]) }
  end

  private

  # `name` is already known when this comes from a picked autocomplete
  # suggestion, so skip the extra reverse-geocode round trip -- it's only
  # nil for the raw-coordinates path (geolocation_controller.js).
  def update_from_coordinates(latitude, longitude, name = nil)
    name ||= reverse_geocode(latitude, longitude)

    current_user.update!(
      current_latitude: latitude,
      current_longitude: longitude,
      current_location_name: name
    )
    head :ok
  end

  def update_from_query(query)
    result = geocode(query)

    return render json: { error: "Couldn't find that place" }, status: :unprocessable_entity unless result

    current_user.update!(
      current_latitude: result[:lat],
      current_longitude: result[:lng],
      current_location_name: result[:name]
    )
    render json: { latitude: result[:lat], longitude: result[:lng], name: result[:name] }, status: :ok
  end

  def suggest(query, limit: 5)
    return [] if query.blank?

    response = Faraday.get(GEOCODE_URL) do |req|
      req.params["q"] = query
      req.params["autocomplete"] = true
      req.params["limit"] = limit
      req.params["language"] = "en"
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    JSON.parse(response.body)["features"].to_a.map { |feature| feature_to_suggestion(feature) }
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

  def reverse_geocode(latitude, longitude)
    response = Faraday.get(REVERSE_GEOCODE_URL) do |req|
      req.params["longitude"] = longitude
      req.params["latitude"] = latitude
      req.params["language"] = "en"
      req.params["types"] = "neighborhood,locality,place"
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    feature = JSON.parse(response.body)["features"]&.first
    feature&.dig("properties", "name") || feature&.dig("properties", "place_formatted")
  rescue StandardError
    nil
  end
end
