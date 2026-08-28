# app/services/poi_finder.rb
#
# Finds real nearby places (points of interest, "POIs") for a given
# location and a list of Mapbox category names (e.g. "park", "market").
# This is the first real-world step in the route pipeline: before any AI
# is involved, we ask Mapbox "what's actually near this person" so later
# steps have real places to choose from instead of made-up ones.
class PoiFinder
  # Mapbox's endpoint for searching by category near a point.
  SEARCH_BOX_CATEGORY_URL = "https://api.mapbox.com/search/searchbox/v1/category"

  # How far around the person to search, in meters. 1500m is roughly a
  # 15-20 minute walk, so results should still be a reasonable distance
  # from where someone's starting.
  DEFAULT_RADIUS_METERS = 1500

  # How many places to ask Mapbox for per category. We don't need
  # hundreds of results - just enough for the next step (the LLM) to have
  # a handful of real options to pick from.
  DEFAULT_LIMIT_PER_CATEGORY = 10

  # A simple, predictable object to hand back to whoever calls this
  # service, instead of raising exceptions everywhere. `success?` tells
  # the caller whether it worked, `pois` holds the results, `error` holds
  # a message if something went wrong.
  Result = Struct.new(:success?, :pois, :error, keyword_init: true)

  # lat/lng: the person's current location
  # categories: which kinds of places to look for (e.g. ["park", "garden"])
  def initialize(lat:, lng:, categories:, radius_meters: DEFAULT_RADIUS_METERS,
                 limit_per_category: DEFAULT_LIMIT_PER_CATEGORY)
    @lat = lat.to_f
    @lng = lng.to_f
    @categories = Array(categories)
    @radius_meters = radius_meters
    @limit_per_category = limit_per_category
  end

  # The main entry point - call this to actually run the search.
  # Loops over every category we were given, fetches results for each one
  # from Mapbox, combines them all into one list, and removes duplicates
  # (in case a place matches more than one category, e.g. a place tagged
  # as both "park" and "garden").
  def call
    all_pois = @categories.flat_map { |category| fetch_category(category) }
    Result.new(success?: true, pois: dedupe(all_pois))
  rescue StandardError => e
    # If anything goes wrong (network error, bad response, etc.), don't
    # crash - just report it back as a failed Result so the caller can
    # decide what to do (e.g. skip this theme rather than breaking the
    # whole page).
    Result.new(success?: false, error: e.message, pois: [])
  end

  private

  # Makes one request to Mapbox for a single category (e.g. just "park"),
  # and turns Mapbox's response into plain, simple hashes we can work with
  # later - just the id, name, category, and coordinates of each place.
  def fetch_category(category)
    response = Faraday.get("#{SEARCH_BOX_CATEGORY_URL}/#{category}") do |req|
      req.params["proximity"] = "#{@lng},#{@lat}" # Mapbox wants "lng,lat", not "lat,lng"
      req.params["limit"] = @limit_per_category
      req.params["access_token"] = ENV.fetch("MAPBOX_ACCESS_TOKEN", nil)
    end

    body = JSON.parse(response.body)

    # Mapbox returns an error message instead of features when something's
    # wrong (bad category name, bad token, etc.) - catch that explicitly
    # rather than silently returning an empty list, so the real problem
    # doesn't get hidden.
    raise "Mapbox error (#{category}): #{body['message']}" if body["message"] && body["features"].nil?

    # Mapbox's response is deeply nested GeoJSON - pull out just the
    # handful of fields we actually need from each result.
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

  # If the same place showed up under more than one category (e.g. it's
  # tagged both "park" and "garden"), only keep it once - the LLM doesn't
  # need to see the same place twice.
  def dedupe(pois)
    pois.uniq { |poi| poi[:id] }
  end
end
