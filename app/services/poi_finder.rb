class PoiFinder
  NEARBY_SEARCH_URL = "https://places.googleapis.com/v1/places:searchNearby"
  FIELD_MASK = "places.id,places.displayName,places.location,places.types"

  DEFAULT_RADIUS_METERS = 1500 # roughly a 15-20 minute walk
  DEFAULT_LIMIT_PER_CATEGORY = 10

  Result = Struct.new(:success?, :pois, :error, keyword_init: true)

  def initialize(lat:, lng:, categories:, radius_meters: DEFAULT_RADIUS_METERS,
                 limit_per_category: DEFAULT_LIMIT_PER_CATEGORY)
    @lat = lat.to_f
    @lng = lng.to_f
    @categories = Array(categories)
    @radius_meters = radius_meters
    @limit_per_category = limit_per_category
  end

  def call
    all_pois = @categories.flat_map { |category| fetch_category(category) }
    Result.new(success?: true, pois: dedupe(all_pois))
  rescue StandardError => e
    Result.new(success?: false, error: e.message, pois: [])
  end

  private

  def fetch_category(category)
    response = Faraday.post(NEARBY_SEARCH_URL) do |req|
      apply_headers(req)
      req.body = request_body(category).to_json
    end

    body = JSON.parse(response.body)

    # Google returns an "error" object instead of "places" when something's
    # wrong -- catch that explicitly rather than silently returning an empty list.
    raise "Google Places error (#{category}): #{body.dig('error', 'message')}" if body["error"]

    (body["places"] || []).map { |place| poi_from_place(place, category) }
  end

  def apply_headers(req)
    req.headers["Content-Type"] = "application/json"
    req.headers["X-Goog-Api-Key"] = ENV.fetch("GOOGLE_PLACES_API_KEY", nil)
    req.headers["X-Goog-FieldMask"] = FIELD_MASK
  end

  def request_body(category)
    {
      includedTypes: [category],
      maxResultCount: @limit_per_category,
      languageCode: "en",
      locationRestriction: {
        circle: { center: { latitude: @lat, longitude: @lng }, radius: @radius_meters }
      }
    }
  end

  def poi_from_place(place, category)
    lat = place.dig("location", "latitude")
    lng = place.dig("location", "longitude")

    {
      id: place["id"],
      name: place.dig("displayName", "text"),
      category: category,
      lat: lat,
      lng: lng,
      distance_meters: GeoDistance.haversine(@lat, @lng, lat, lng).round
    }
  end

  def dedupe(pois)
    pois.uniq { |poi| poi[:id] }
  end
end
