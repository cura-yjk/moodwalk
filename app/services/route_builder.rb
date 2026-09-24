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
  # route actually chosen, after routing has settled (see #call).
  #
  # unavailable marks a failure to reach Google at all, as opposed to finding
  # nothing: JourneysController only suggests a longer walk for the second.
  Result = Struct.new(:success?, :journey, :waypoints, :error, :unavailable, keyword_init: true)

  # Translates a chosen duration into a target route distance (and, below, a
  # POI search radius) to aim for. Walk owns the pace so that the number we
  # plan with and the number Mapbox estimates the finished route at are the
  # same one -- see Walk::WALKING_METERS_PER_SECOND.
  WALKING_METERS_PER_MINUTE = Walk.walking_meters_per_minute

  # With no duration, a pass that can't build a route at all - too few places
  # found, or every option turned down by Mapbox - searches again this many
  # times in all, twice as wide each time. With a duration it doesn't: the
  # first search already reaches as far as a walk that long can, and
  # measured across three areas, every walk built from a wider search came
  # back 30-60 minutes long for a 20-minute request. JourneysController says
  # so instead.
  #
  # A route the wrong length no longer searches again: ShortlistRouter
  # re-picks from the places already found. Searching again used to cost a
  # full set of Google calls per retry, and rarely fixed the length.
  MAX_ATTEMPTS = 3

  # How far a route's length may stray from the duration picked, either way.
  TOLERANCE_RATIO = 0.25

  # Mapbox calls per build, across every pass and both shapes. Without it a
  # "no rush" build that kept failing could make 18: three passes, each
  # routing a loop and a one-way shortlist of three. Six is one full pass;
  # widening mostly helps when a pass found too few places to route at all,
  # which costs no Mapbox calls.
  MAX_ROUTINGS_PER_BUILD = 6
  ROUTINGS_SPENT = JourneyGenerator::Result.new(success?: false, error: "No route found nearby").freeze

  # variety_seed rides through to PoiSelector, which uses it to index into its
  # shortlist of good combinations rather than always returning the single
  # best one -- see PoiSelector::VARIETY_POOL_SIZE. Nil keeps the old
  # behaviour, which is what seeding and the retry tests below rely on.
  def initialize(lat:, lng:, theme_key:, duration_minutes: nil, variety_seed: nil)
    @lat = lat.to_f
    @lng = lng.to_f
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
    @target_distance = WalkReach.target_distance(duration_minutes)
    @target_seconds = duration_minutes.to_f * 60 if duration_minutes.present?
    @duration_minutes = duration_minutes
    @variety_seed = variety_seed
  end

  def call
    result = build_widening
    apply_fallback_text(result) if result.success?
    result
  rescue ArgumentError => e
    failure(e.message)
  end

  private

  # Searches as far as a walk this long reaches (see WalkReach). Only with no
  # duration does a failed pass widen it.
  def build_widening
    radius = WalkReach.search_radius(@duration_minutes)
    result = nil

    (@target_distance ? 1 : MAX_ATTEMPTS).times do
      result = attempt(radius)
      # A wider search couldn't help while Google or Mapbox is down.
      break if result.success? || result.unavailable

      radius *= 2
    end

    result
  end

  def attempt(radius)
    poi_result = PoiFinder.new(lat: @lat, lng: @lng, categories: @theme[:categories], radius_meters: radius).call
    return failure(poi_result.error, unavailable: true) unless poi_result.success?

    build_from(poi_result.pois)
  end

  # Deliberately does NOT write the description. Mapbox rejects routes often
  # enough (dead ends, u-turns, unroutable waypoints) that describing first
  # meant paying for prose about routes that turned out not to exist - and
  # more than one route is routed per build, so it also meant descriptions
  # of routes that were thrown away.
  #
  # Loop first, if the places make one worth walking; one-way if they don't -
  # or if every loop option turns out retraced or the wrong length once
  # Mapbox has routed it, which the plan can't show. From a real doorstep,
  # every loop option re-walked 24-27% of itself while a one-way walk from
  # the same places re-walked 3%, and the loop was kept because the shape
  # used to be settled before anything was routed. Whichever shape's route
  # ranks better wins.
  def build_from(pois)
    tried = []

    [true, false].each do |round_trip|
      routed = route_shape(pois, round_trip) or next
      tried << [routed, round_trip]
      break if routed.acceptable
    end

    choose(tried)
  end

  # Sets @round_trip to the winner's shape, which the title is written for.
  def choose(tried)
    routed, @round_trip = tried.select { |result, _| result.success? }.min_by { |result, _| result.rank }
    return failure(tried.last.first.error, unavailable: @mapbox_down.present?) unless routed

    Result.new(success?: true, journey: routed.journey, waypoints: routed.waypoints)
  end

  # The selector's pick for one shape, routed first; if its real route is the
  # wrong length, re-walks too much of itself, or Mapbox turns it down, the
  # next-best waypoints are routed from the same places - see
  # ShortlistRouter. Nil when these places make no loop worth walking (see
  # PoiSelector::MIN_LOOP_ROUNDNESS), which leaves it to one-way.
  def route_shape(pois, round_trip)
    selection = poi_selector(pois, round_trip: round_trip).call
    return if round_trip && !selection.success?
    return ShortlistRouter::Result.new(success?: false, error: selection.error) unless selection.success?

    options = [selection.waypoints, *selection.alternatives]
    ShortlistRouter.new(options, target_seconds: @target_seconds, tolerance: TOLERANCE_RATIO) do |waypoints|
      generate_journey(waypoints, round_trip: round_trip)
    end.call
  end

  # Every journey leaves here with a description, written in plain Ruby.
  #
  # The LLM is no longer called in the request at all: it was two thirds of a
  # route's generation time (~3s of a ~4.5s build), it is the one dependency
  # that can be down on its own while Google and Mapbox are fine, and nothing
  # downstream needs its output. JourneyDescriptionJob replaces this text with
  # the real description once the journey is saved -- see
  # JourneysController#create.
  # Both written here rather than at generation time, because both need the
  # waypoints the selector chose -- and the name also needs the neighbourhood,
  # which JourneyGenerator geocodes while building the record.
  def apply_fallback_text(result)
    journey = result.journey
    journey.description = RouteDescriber.fallback_for(theme_key: @theme_key, waypoints: result.waypoints)
    journey.name = JourneyTitle.for(journey: journey, waypoints: result.waypoints, round_trip: @round_trip)
  end

  def poi_selector(pois, round_trip:)
    PoiSelector.new(
      lat: @lat, lng: @lng, pois: pois, target_distance_meters: @target_distance,
      round_trip: round_trip, variety_seed: @variety_seed
    )
  end

  # Stops asking Mapbox once it's down: another call would only fail too.
  def generate_journey(waypoints, round_trip:)
    return ROUTINGS_SPENT if @mapbox_down || (@routings = @routings.to_i + 1) > MAX_ROUTINGS_PER_BUILD

    generation = journey_generator(waypoints, round_trip).call
    @mapbox_down ||= generation.unavailable
    generation
  end

  def journey_generator(waypoints, round_trip)
    JourneyGenerator.new(
      lat: @lat, lng: @lng, waypoints: waypoints, theme_key: @theme_key,
      # Replaced by apply_fallback_text once the record exists and its
      # neighbourhood has been resolved; JourneyGenerator needs a name here.
      name: @theme[:label],
      round_trip: round_trip,
      location_name: location_name
    )
  end

  # The start never moves between the routes tried, so neither does its
  # neighbourhood: one lookup per build, not one per route routed.
  def location_name
    return @location_name if defined?(@location_name)

    @location_name = MapboxGeocoder.reverse(@lat, @lng)
  end

  def failure(error_message, unavailable: false)
    Result.new(success?: false, error: error_message, unavailable: unavailable)
  end
end
