# app/services/route_builder.rb
#
# The single entry point for "user tapped a theme" -> saved Journey.
# Chains the pipeline described in the design doc:
#
#   theme_key -> THEMES lookup (no LLM call)
#             -> PoiFinder        (real nearby POIs from Mapbox Search Box)
#             -> LlmPoiCurator    (LLM selects/orders POIs + writes description)
#             -> JourneyGenerator (real Directions route, no synthetic loop)
#
# Each stage can fail independently (no candidates found, LLM picked
# nothing valid, Directions had no route) — RouteBuilder stops at the
# first failure and surfaces that stage's error rather than a generic one,
# since "no parks nearby" and "Mapbox couldn't route between these points"
# need different handling upstream (e.g. in the controller).
#
# Usage:
#   result = RouteBuilder.new(lat:, lng:, theme_key: :nature_escape).call
#   result.success? ? result.journey : result.error

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
