# theme_key -> PoiFinder -> LlmPoiCurator -> JourneyGenerator.
# Stops at the first stage that fails and surfaces that stage's error,
# since "no parks nearby" and "Mapbox couldn't route between these
# points" need different handling upstream.
class RouteBuilder
  Result = Struct.new(:success?, :journey, :error, keyword_init: true)

  def initialize(lat:, lng:, theme_key:)
    @lat = lat.to_f
    @lng = lng.to_f
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
  end

  def call
    poi_result = find_pois
    return failure(poi_result.error) unless poi_result.success?

    curation = curate(poi_result.pois)
    return failure(curation.error) unless curation.success?

    generation = generate_journey(curation)
    return failure(generation.error) unless generation.success?

    Result.new(success?: true, journey: generation.journey)
  rescue ArgumentError => e
    failure(e.message)
  end

  private

  def find_pois
    PoiFinder.new(lat: @lat, lng: @lng, categories: @theme[:categories]).call
  end

  def curate(pois)
    LlmPoiCurator.new(theme_key: @theme_key, pois: pois).call
  end

  def generate_journey(curation)
    JourneyGenerator.new(
      lat: @lat,
      lng: @lng,
      waypoints: curation.waypoints,
      description: curation.description,
      theme_key: @theme_key,
      name: @theme[:label]
    ).call
  end

  def failure(error_message)
    Result.new(success?: false, error: error_message)
  end
end
