# theme_key -> PoiFinder -> LlmPoiCurator -> JourneyGenerator.
# Stops at the first stage that fails and surfaces that stage's error,
# since "no parks nearby" and "Mapbox couldn't route between these
# points" need different handling upstream.
class RouteBuilder
  Result = Struct.new(:success?, :journey, :error, keyword_init: true)

  # Average adult walking speed, used to translate a chosen duration into a
  # target route distance (and, below, a POI search radius) to aim for.
  WALKING_METERS_PER_MINUTE = 80

  # When a duration is given, the real-waypoint route JourneyGenerator comes
  # back with won't exactly hit the target distance (fixed POIs, not a
  # rescalable synthetic loop) - so, same idea as JourneyGenerator's own
  # synthetic-loop retry, widen/narrow the POI search radius and try again
  # up to this many times if the actual distance is off by more than
  # TOLERANCE_RATIO.
  MAX_ATTEMPTS = 3
  TOLERANCE_RATIO = 0.25

  def initialize(lat:, lng:, theme_key:, duration_minutes: nil)
    @lat = lat.to_f
    @lng = lng.to_f
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
    @target_distance = duration_minutes.to_f * WALKING_METERS_PER_MINUTE if duration_minutes.present?
  end

  def call
    return call_toward_target if @target_distance

    poi_result = PoiFinder.new(lat: @lat, lng: @lng, categories: @theme[:categories]).call
    return failure(poi_result.error) unless poi_result.success?

    build_from(poi_result.pois)
  rescue ArgumentError => e
    failure(e.message)
  end

  private

  # A loop covers roughly the round trip of its farthest waypoint, so start
  # the search about half the target distance out, then rescale by how far
  # off the actual route came out - exactly JourneyGenerator's own
  # rescale-and-retry, just one level up (adjusting which real places are in
  # play rather than a synthetic bearing/radius).
  def call_toward_target
    radius = @target_distance / 2.0
    result = nil

    MAX_ATTEMPTS.times do |attempt|
      result = attempt_toward_target(radius)
      return result if attempt == MAX_ATTEMPTS - 1 || on_target?(result)

      radius = next_radius(result, radius)
    end

    result
  end

  def attempt_toward_target(radius)
    poi_result = PoiFinder.new(lat: @lat, lng: @lng, categories: @theme[:categories], radius_meters: radius).call
    return failure(poi_result.error) unless poi_result.success?

    build_from(poi_result.pois)
  end

  def on_target?(result)
    return false unless result.success?

    ((result.journey.distance_meters / @target_distance) - 1).abs <= TOLERANCE_RATIO
  end

  # Too few candidates in range -> widen the net; a route that came back
  # the wrong length -> rescale the same way JourneyGenerator's own
  # synthetic-loop retry does.
  def next_radius(result, radius)
    return radius * 2 unless result.success?

    radius * (@target_distance / result.journey.distance_meters)
  end

  def build_from(pois)
    curation = curate(pois)
    return failure(curation.error) unless curation.success?

    generation = generate_journey(curation)
    return failure(generation.error) unless generation.success?

    Result.new(success?: true, journey: generation.journey)
  end

  def curate(pois)
    LlmPoiCurator.new(theme_key: @theme_key, pois: pois, target_distance_meters: @target_distance).call
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
