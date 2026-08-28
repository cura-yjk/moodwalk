class LocationsController < ApplicationController
  GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward"
  REVERSE_GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/reverse"

  # This one action handles two different situations, because two
  # different parts of the homepage both save to "/location":
  #
  #   1. app/javascript/controllers/geolocation_controller.js runs
  #      automatically on page load and sends the browser's raw
  #      { latitude:, longitude: } -- no place name attached.
  #
  #   2. app/javascript/controllers/location_search_controller.js runs
  #      when the user types a place into the "Change" search box and
  #      sends { query: "Shibuya" } -- just text, no coordinates yet.
  #
  # Whichever one calls in, we want the same end result: the user ends up
  # with latitude, longitude, AND a readable place name saved, so the
  # homepage can both show "Starting from X" and run nearby-journey
  # searches.
  def update
    if params[:query].present?
      update_from_query(params[:query])
    else
      update_from_coordinates(params[:latitude], params[:longitude])
    end
  rescue StandardError => e
    # Catch-all so a Mapbox hiccup or any other failure comes back as a
    # normal JSON error instead of crashing the request.
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Path for the automatic browser-geolocation flow. We already have
  # coordinates here, we just don't have a name yet -- so we look one up
  # via reverse geocoding before saving, so the homepage isn't stuck
  # showing raw numbers.
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

  # Path for the manual "search for a place" flow. Here we start with
  # only a typed-in name and have to look up coordinates for it -- the
  # opposite direction from update_from_coordinates above.
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

  # Turns typed text like "Shibuya" into coordinates + a clean display
  # name, using Mapbox's search API. We only ever take the first result
  # since Mapbox already sorts by relevance -- no need to pick among
  # several ourselves.
  def geocode(query)
    response = Faraday.get(GEOCODE_URL) do |req|
      req.params["q"] = query
      req.params["limit"] = 1
      req.params["language"] = "en"
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    feature = JSON.parse(response.body)["features"]&.first
    return nil unless feature

    # Mapbox returns coordinates as [longitude, latitude], in that order --
    # easy to mix up, so we unpack it explicitly here.
    lng, lat = feature.dig("geometry", "coordinates")
    name = feature.dig("properties", "name") || feature.dig("properties", "place_formatted")
    { lat: lat, lng: lng, name: name }
  end

  # Does the opposite of geocode above: given raw coordinates from the
  # browser, ask Mapbox what place that actually is, so we have something
  # readable to show ("Meguro") instead of a lat/lng pair.
  #
  # This step is a nice-to-have, not essential -- if Mapbox fails or
  # returns nothing, we just save no name and move on rather than
  # blocking the whole location update over it.
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
