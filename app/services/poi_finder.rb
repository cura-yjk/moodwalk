class PoiFinder
  NEARBY_SEARCH_URL = "https://places.googleapis.com/v1/places:searchNearby"
  FIELD_MASK = "places.id,places.displayName,places.location,places.types"

  DEFAULT_RADIUS_METERS = 1500 # roughly a 15-20 minute walk

  # Nearby Search is billed per request, not per result, so asking for the
  # maximum costs exactly what asking for ten did and hands PoiSelector more to
  # choose from. 20 is the API's ceiling.
  DEFAULT_LIMIT_PER_CATEGORY = 20

  # How long a category's results stay good for.
  #
  # Which parks exist near a corner does not change minute to minute, and the
  # same corner gets searched repeatedly: RouteBuilder retries at several radii
  # within one generation, a user who turns down a walk asks again from the
  # same doorstep, and two people setting off from the same station search the
  # same ground. Well inside what the Places terms allow for holding results.
  CACHE_TTL = 15.minutes

  # ~110m of latitude. Two starts inside the same cell share results: the
  # search centre shifts by less than a tenth of the smallest radius we ever
  # use, which is not enough to change which places are nearby.
  CACHE_LOCATION_PRECISION = 3

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
    Result.new(success?: true, pois: dedupe(fetch_all_categories))
  rescue StandardError => e
    Result.new(success?: false, error: e.message, pois: [])
  end

  # Whether at least `minimum` places of any of these categories are within
  # the radius - asked in one request for all of them, where #call makes one
  # per category. Google returns at most 20 places for the lot, so this can
  # say whether a route is worth trying but can't stand in for the search a
  # route is built from. A failed request counts as no.
  def enough_nearby?(minimum)
    key = cache_key(@categories.sort.join("+"))
    places = Rails.cache.fetch(key, expires_in: CACHE_TTL) { request_places(@categories) }
    places.size >= minimum
  rescue StandardError => e
    Rails.logger.warn("PoiFinder#enough_nearby? failed: #{e.class}: #{e.message}")
    false
  end

  private

  # One request per category, issued concurrently.
  #
  # These are pure I/O waits on Google, so running them in series made a themed
  # search cost the sum of every category rather than the slowest single one --
  # measured at 818ms for calm's seven categories against 290ms in parallel,
  # and themes now carry up to eight. Thread#value re-raises in the caller, so
  # a failing category still surfaces through #call's rescue exactly as before.
  #
  # The executor wrap is what makes autoloading safe inside these threads; the
  # requests themselves share no state, since each builds its own connection.
  def fetch_all_categories
    return fetch_category(@categories.first) if @categories.one?

    @categories
      .map { |category| Thread.new { Rails.application.executor.wrap { fetch_category(category) } } }
      .flat_map(&:value)
  end

  # Google's own answer is what gets cached, not the POIs built from it: the
  # cache key rounds the search centre to a cell, while distance_meters below
  # is measured from where the walker actually is. Caching the finished POIs
  # would hand the second walker in a cell the first one's distances.
  #
  # A failed request raises out of the block, so nothing is stored and the next
  # attempt asks Google again. An empty result is stored, because a category
  # with nothing nearby is an answer worth not paying for twice.
  def fetch_category(category)
    places = Rails.cache.fetch(cache_key(category), expires_in: CACHE_TTL) { request_places([category]) }

    places.map { |place| poi_from_place(place, category) }
  end

  def cache_key(category)
    [
      # v2: matched on primary type. v1 entries hold places matched on any tag.
      "poi_finder", "v2", category,
      @lat.round(CACHE_LOCATION_PRECISION), @lng.round(CACHE_LOCATION_PRECISION),
      @radius_meters.round, @limit_per_category
    ].join("/")
  end

  def request_places(types)
    response = ExternalApi.connection.post(NEARBY_SEARCH_URL) do |req|
      apply_headers(req)
      req.body = request_body(types).to_json
    end

    body = ExternalApi.parse_json(response, service: "Google Places")

    # Google returns an "error" object instead of "places" when something's
    # wrong -- catch that explicitly rather than silently returning an empty list.
    raise "Google Places error (#{types.join(', ')}): #{body.dig('error', 'message')}" if body["error"]

    body["places"] || []
  end

  def apply_headers(req)
    req.headers["Content-Type"] = "application/json"
    req.headers["X-Goog-Api-Key"] = ENV.fetch("GOOGLE_PLACES_API_KEY", nil)
    req.headers["X-Goog-FieldMask"] = FIELD_MASK
  end

  # includedPrimaryTypes, not includedTypes: the latter matches any type a
  # place is tagged with, and Google tags liberally - measured in Tokyo, a bar
  # came back as a hiking_area and a massage shop as a campground. A place's
  # primary type is what it actually is.
  def request_body(types)
    {
      includedPrimaryTypes: types,
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
