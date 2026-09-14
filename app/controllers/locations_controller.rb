class LocationsController < ApplicationController
  GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward"

  # Mapbox returns *something* for almost any input: "zzzqqqxxx not a place
  # 123" comes back as an address in Barcelona. Guessed address matches carry a
  # match_code whose confidence is "low"; genuine place/neighborhood matches
  # carry no match_code at all. Dropping the low-confidence ones is what stops
  # a typo silently relocating someone to another continent.
  LOW_CONFIDENCE = "low"

  # Three ways in, all from the location bar (shared/_location_bar): coordinates
  # from the browser's Geolocation API, coordinates from a suggestion the user
  # picked (which carries its own name, so no second geocode), or -- as a
  # fallback -- a raw place name typed by hand.
  def update
    if coordinates_given?
      update_from_coordinates(latitude_param, longitude_param, params[:name].presence)
    else
      update_from_query(params[:query].to_s.strip)
    end
  rescue StandardError => e
    # The message is for the log, not the client: it can carry provider and
    # internal detail, and there is nothing the user could do with it.
    Rails.logger.error("LocationsController#update failed: #{e.class}: #{e.message}")
    render json: { error: "Couldn't update your location just now." }, status: :unprocessable_entity
  end

  # Typeahead for the location field. Returning several named places with the
  # district they sit in is what stops someone committing to a wrong guess:
  # Mapbox answers almost any input, so the user picks a real result rather
  # than the app silently taking the first one.
  def autocomplete
    render json: { results: suggest(params[:query].to_s.strip) }
  end

  private

  # Three kinds of write, distinguished by `source`:
  #
  #   "manual"  picking a suggestion or a recent place -- pins the location
  #   "detect"  the user pressing "Use my current location" -- unpins it
  #   (absent)  the background sync on page load
  #
  # Only the first two may move a pinned location. The background sync is
  # refused, because it is what used to quietly undo a deliberate choice on the
  # next page load -- and enforcing it here rather than only in the browser
  # means a tab left open from before the pin cannot undo it either.
  def manual_choice?
    params[:source] == "manual"
  end

  def background_sync?
    params[:source].blank?
  end

  def pinned_elsewhere?
    background_sync? && current_user.location_manually_set
  end

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
    return head :no_content if pinned_elsewhere?

    name ||= MapboxGeocoder.reverse(latitude, longitude)

    current_user.move_to!(latitude: latitude, longitude: longitude, name: name, manual: manual_choice?)
    head :ok
  end

  def update_from_query(query)
    return not_found("Enter a town, district or landmark.") if query.blank?

    result = geocode(query)
    return not_found("Couldn't find that place. Try a nearby landmark or district.") unless result

    # Typing a place name is always a deliberate choice.
    current_user.move_to!(latitude: result[:lat], longitude: result[:lng], name: result[:name], manual: true)
    render json: { latitude: result[:lat], longitude: result[:lng], name: result[:name] }, status: :ok
  end

  def not_found(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  # Nearby places first, but never *only* nearby places.
  #
  # Mapbox treats proximity as a hard filter here rather than a soft bias:
  # searching "Paris" with proximity set to Tokyo returns nothing at all, not
  # Paris ranked lower. So search locally first -- which is what keeps a
  # near-miss from resolving to a same-sounding place 600km away -- and fall
  # back to a global search when nothing nearby matches, since that is exactly
  # when someone is looking for another city.
  def suggest(query, limit: 5)
    return [] if query.blank?

    nearby = fetch_suggestions(query, limit, proximity)
    return nearby if nearby.any?
    return [] if proximity.nil? # already global; no second search to make

    fetch_suggestions(query, limit, nil)
  end

  def fetch_suggestions(query, limit, proximity)
    response = geocode_request(query, limit, proximity)

    ExternalApi.parse_json(response, service: "Mapbox Geocoding")["features"]
               .to_a.select { |feature| confident_match?(feature) }
               .map { |feature| feature_to_suggestion(feature) }
  end

  def geocode_request(query, limit, proximity)
    ExternalApi.connection.get(GEOCODE_URL) do |req|
      req.params["q"] = query
      req.params["autocomplete"] = true
      req.params["limit"] = limit
      req.params["language"] = "en"
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
