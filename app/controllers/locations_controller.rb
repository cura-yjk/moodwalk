class LocationsController < ApplicationController
  GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward"
  REVERSE_GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/reverse"

  def update
    if params[:query].present?
      update_from_query(params[:query])
    else
      update_from_coordinates(params[:latitude], params[:longitude])
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def update_from_coordinates(latitude, longitude)
    if latitude.blank? || longitude.blank?
      return render json: { error: "Missing coordinates" }, status: :unprocessable_entity
    end

    name = reverse_geocode(latitude, longitude)

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

  def geocode(query)
    response = Faraday.get(GEOCODE_URL) do |req|
      req.params["q"] = query
      req.params["limit"] = 1
      req.params["language"] = "en"
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    feature = JSON.parse(response.body)["features"]&.first
    return nil unless feature

    # Mapbox returns coordinates as [longitude, latitude] -- easy to mix up.
    lng, lat = feature.dig("geometry", "coordinates")
    name = feature.dig("properties", "name") || feature.dig("properties", "place_formatted")
    { lat: lat, lng: lng, name: name }
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
