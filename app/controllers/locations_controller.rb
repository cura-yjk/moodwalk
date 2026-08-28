class LocationsController < ApplicationController
  GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward"

  # Called by two different callers:
  #   - app/javascript/controllers/geolocation_controller.js sends
  #     { latitude:, longitude: } straight from the browser.
  #   - app/javascript/controllers/location_search_controller.js (the
  #     "Change" link) sends { query: "Shibuya" } - a free-text place name
  #     that needs geocoding server-side before we trust it as coordinates.
  # Same pattern as WalksController#attach_photo: a plain JSON PATCH, not
  # a real form.
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

    current_user.update!(current_latitude: latitude, current_longitude: longitude)
    head :ok
  end

  def update_from_query(query)
    coords = geocode(query)

    return render json: { error: "Couldn't find that place" }, status: :unprocessable_entity unless coords

    current_user.update!(current_latitude: coords[:lat], current_longitude: coords[:lng])
    render json: { latitude: coords[:lat], longitude: coords[:lng] }, status: :ok
  end

  # Forward-geocodes a free-text place name into coordinates via Mapbox's
  # Geocoding v6 API. Takes the single most relevant result - results are
  # already ordered by relevance, so no ranking logic needed here.
  def geocode(query)
    response = Faraday.get(GEOCODE_URL) do |req|
      req.params["q"] = query
      req.params["limit"] = 1
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    body = JSON.parse(response.body)
    feature = body["features"]&.first
    return nil unless feature

    lng, lat = feature.dig("geometry", "coordinates")
    { lat: lat, lng: lng }
  end
end
