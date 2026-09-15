# theme_key -> PoiFinder -> PoiSelector -> JourneyGenerator -> RouteDescriber.
#
# Stops at the first *route-building* stage that fails and surfaces that
# stage's error, since "no parks nearby," "couldn't find a good waypoint
# combination," and "Mapbox couldn't route between these points" all need
# different handling upstream.
#
# RouteDescriber is the exception, and runs last for that reason: it only
# writes the card's prose, so it can't fail a route. It used to run in the
# middle of the pipeline and abort the build, which meant an LLM outage took
# down route generation entirely even while Google and Mapbox were healthy.
# See #describe!.
class RouteBuilder
  # waypoints ride along so the description can be written once, for the
  # winning attempt only, after the retry loop has settled (see #call).
  Result = Struct.new(:success?, :journey, :waypoints, :error, keyword_init: true)

  # Translates a chosen duration into a target route distance (and, below, a
  # POI search radius) to aim for. Walk owns the pace so that the number we
  # plan with and the number Mapbox estimates the finished route at are the
  # same one -- see Walk::WALKING_METERS_PER_SECOND.
  WALKING_METERS_PER_MINUTE = Walk.walking_meters_per_minute

  # When a duration is given, the real-waypoint route JourneyGenerator comes
  # back with won't exactly hit the target distance (fixed POIs, not a
  # rescalable synthetic loop) - so, same idea as JourneyGenerator's own
  # synthetic-loop retry, widen/narrow the POI search radius and try again
  # up to this many times if the actual distance is off by more than
  # TOLERANCE_RATIO.
  MAX_ATTEMPTS = 3
  TOLERANCE_RATIO = 0.25

  # A loop only looks like an actual loop if its waypoints spread out across
  # different directions from the start (see PoiSelector's bearing_spread,
  # 0-180) - below this, the outbound and return legs would retrace nearly
  # the same streets, so a one-way trip suits the real candidates better.
  # Not everyone wants to walk back the way they came anyway.
  ROUND_TRIP_SPREAD_THRESHOLD_DEGREES = 90

  # variety_seed rides through to PoiSelector, which uses it to index into its
  # shortlist of good combinations rather than always returning the single
  # best one -- see PoiSelector::VARIETY_POOL_SIZE. Nil keeps the old
  # behaviour, which is what seeding and the retry tests below rely on.
  def initialize(lat:, lng:, theme_key:, duration_minutes: nil, variety_seed: nil)
    @lat = lat.to_f
    @lng = lng.to_f
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
    @target_distance = duration_minutes.to_f * WALKING_METERS_PER_MINUTE if duration_minutes.present?
    @variety_seed = variety_seed
  end

  def call
    result = @target_distance ? call_toward_target : attempt
    apply_fallback_description(result) if result&.success?
    result
  rescue ArgumentError => e
    failure(e.message)
  end

  private

  # One pass of the pipeline at a given search radius. The retry loop below
  # calls this repeatedly with a rescaled radius; with no target duration
  # there's nothing to rescale toward, so it runs once at PoiFinder's default.
  def attempt(radius = PoiFinder::DEFAULT_RADIUS_METERS)
    poi_result = PoiFinder.new(lat: @lat, lng: @lng, categories: @theme[:categories], radius_meters: radius).call
    return failure(poi_result.error) unless poi_result.success?

    build_from(poi_result.pois)
  end

  # A loop covers roughly the round trip of its farthest waypoint, so start
  # the search about half the target distance out, then rescale by how far
  # off the actual route came out - exactly JourneyGenerator's own
  # rescale-and-retry, just one level up (adjusting which real places are in
  # play rather than a synthetic bearing/radius).
  def call_toward_target
    radius = @target_distance / 2.0
    best = nil

    # attempt_number, not attempt: the method below is called inside this block
    # and a bare `attempt` would resolve to the counter instead.
    MAX_ATTEMPTS.times do |attempt_number|
      result = attempt(radius)
      best = pick_best(best, result)
      return best if attempt_number == MAX_ATTEMPTS - 1 || on_target?(result)

      radius = next_radius(result, radius)
    end

    best
  end

  # A later attempt can come back worse than an earlier one - e.g. a rescale
  # shrinks the search radius to correct for an over-long route and, in doing
  # so, drops candidate density below what PoiSelector needs. Never let that
  # throw away an earlier attempt that actually worked: only replace the
  # running best with a real improvement (a success beats a failure; between
  # two successes, whichever lands closer to the target distance wins).
  def pick_best(current, candidate)
    return candidate if current.nil?
    return current if current.success? && !candidate.success?
    return candidate if candidate.success? && !current.success?
    return candidate unless current.success?

    distance_off(candidate) < distance_off(current) ? candidate : current
  end

  def distance_off(result)
    (result.journey.distance_meters - @target_distance).abs
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

  # Deliberately does NOT write the description. Mapbox rejects routes often
  # enough (dead ends, u-turns, unroutable waypoints) that describing first
  # meant paying for prose about routes that turned out not to exist - and
  # this method runs once per retry attempt, so it also meant up to
  # MAX_ATTEMPTS descriptions of which all but one were thrown away.
  def build_from(pois)
    selection = select_waypoints(pois)
    return failure(selection.error) unless selection.success?

    generation = generate_journey(selection.waypoints)
    return failure(generation.error) unless generation.success?

    Result.new(success?: true, journey: generation.journey, waypoints: selection.waypoints)
  end

  # Every journey leaves here with a description, written in plain Ruby.
  #
  # The LLM is no longer called in the request at all: it was two thirds of a
  # route's generation time (~3s of a ~4.5s build), it is the one dependency
  # that can be down on its own while Google and Mapbox are fine, and nothing
  # downstream needs its output. JourneyDescriptionJob replaces this text with
  # the real description once the journey is saved -- see
  # JourneysController#create.
  def apply_fallback_description(result)
    result.journey.description = RouteDescriber.fallback_for(theme_key: @theme_key, waypoints: result.waypoints)
  end

  # Try a loop first; only keep it if the real candidates actually spread out
  # enough to look like one. Otherwise, this route is a one-way trip - sets
  # @round_trip as a side effect, since generate_journey needs to build the
  # same shape it was just selected for.
  def select_waypoints(pois)
    loop_selection = poi_selector(pois, round_trip: true).call

    if loop_selection.success? && loop_selection.spread >= ROUND_TRIP_SPREAD_THRESHOLD_DEGREES
      @round_trip = true
      return loop_selection
    end

    @round_trip = false
    poi_selector(pois, round_trip: false).call
  end

  def poi_selector(pois, round_trip:)
    PoiSelector.new(
      lat: @lat, lng: @lng, pois: pois, target_distance_meters: @target_distance,
      round_trip: round_trip, variety_seed: @variety_seed
    )
  end

  def generate_journey(waypoints)
    JourneyGenerator.new(
      lat: @lat,
      lng: @lng,
      waypoints: waypoints,
      theme_key: @theme_key,
      name: @theme[:label],
      round_trip: @round_trip
    ).call
  end

  def failure(error_message)
    Result.new(success?: false, error: error_message)
  end
end
