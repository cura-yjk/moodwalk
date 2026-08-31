class PoiFinder
  SEARCH_BOX_CATEGORY_URL = "https://api.mapbox.com/search/searchbox/v1/category"

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

  # Rough meters-per-degree conversion, good enough at city scale --
  # 1 degree latitude ~= 111,320m everywhere; longitude shrinks with
  # latitude, so it's scaled by cos(lat).
  def bbox
    lat_delta = @radius_meters / 111_320.0
    lng_delta = @radius_meters / (111_320.0 * Math.cos(@lat * Math::PI / 180))

    [
      @lng - lng_delta,
      @lat - lat_delta,
      @lng + lng_delta,
      @lat + lat_delta
    ].join(",")
  end

  def fetch_category(category)
    response = Faraday.get("#{SEARCH_BOX_CATEGORY_URL}/#{category}") do |req|
      req.params["proximity"] = "#{@lng},#{@lat}"
      req.params["bbox"] = bbox
      req.params["limit"] = @limit_per_category
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    body = JSON.parse(response.body)

    # Mapbox returns an error message instead of features when something's
    # wrong -- catch that explicitly rather than silently returning an empty list.
    raise "Mapbox error (#{category}): #{body['message']}" if body["message"] && body["features"].nil?

    (body["features"] || []).map do |feature|
      {
        id: feature.dig("properties", "mapbox_id"),
        name: feature.dig("properties", "name"),
        category: category,
        lat: feature.dig("geometry", "coordinates", 1), # GeoJSON order is [lng, lat]
        lng: feature.dig("geometry", "coordinates", 0)
      }
    end
  end

  def dedupe(pois)
    pois.uniq { |poi| poi[:id] }
  end
end
