# Routes PoiSelector's shortlist in order - its pick, then the alternatives -
# and settles on the first real route that takes the time picked and doesn't
# re-walk its own streets.
#
# Both only show in the route Mapbox returns. The selector plans on straight
# lines, so its length is an estimate; the time shown is Mapbox's, which
# allows for crossings and turns (measured at 68-77 m/min against the 80 the
# app plans with); and retracing - a spur in and out of a
# park, a street walked twice between waypoints - never appears in its plan
# at all. So the way to a better route is to route the next option, which
# costs a Mapbox call and no Google ones: every option comes from places
# already found.
#
# This replaced a retry that searched Google again at a rescaled radius
# whenever the length was off. That cost a full set of category searches per
# retry (measured at about 14 a route) and rarely helped - the selector aimed
# at the same target from much the same places - while a second check on
# retracing, layered inside it, fought it over which route to keep.
class ShortlistRouter
  # More than this share of a route re-walked is retraced enough to notice
  # (see RouteOverlap). Measured on real routes, loops that go round cleanly
  # come in under 5%, and the retraced ones at 12-40%.
  MAX_OVERLAP_RATIO = 0.10

  # Mapbox calls per shortlist, pick included.
  MAX_ROUTINGS = 3

  # acceptable says whether the choice passed both checks, and rank how it
  # compares with another router's choice (lower is better) - RouteBuilder
  # routes the loop options and the one-way ones separately, and keeps the
  # better of the two.
  Result = Struct.new(:success?, :journey, :waypoints, :acceptable, :rank, :error, keyword_init: true)

  # route is called with each option's waypoints and returns a
  # JourneyGenerator::Result. With no target_seconds, any length will do.
  def initialize(options, target_seconds:, tolerance:, &route)
    @options = options.first(MAX_ROUTINGS)
    @target_seconds = target_seconds
    @tolerance = tolerance
    @route = route
  end

  # If nothing passes both checks, the route to keep is the right length if
  # any is - the time the user picked comes first - and the least re-walked
  # among those. If none is the right length, the closest length among those
  # that aren't retraced. A route that retraces a little beats no route. A route
  # Mapbox rejects (dead end, u-turn) moves on to the next option; its reason
  # is surfaced only if every option was rejected.
  def call
    routed, error = route_until_acceptable
    best = routed.min_by { |option| rank(option[:journey]) }
    return Result.new(success?: false, error: error) unless best

    Result.new(
      success?: true, journey: best[:journey], waypoints: best[:waypoints],
      acceptable: acceptable?(best[:journey]), rank: rank(best[:journey])
    )
  end

  private

  # Every option routed successfully, and the last rejection's reason.
  def route_until_acceptable
    routed = []
    error = nil

    @options.each do |waypoints|
      generation = @route.call(waypoints)
      next error = generation.error unless generation.success?

      routed << { journey: generation.journey, waypoints: waypoints }
      break if acceptable?(generation.journey)
    end

    [routed, error]
  end

  def acceptable?(journey)
    right_length?(journey) && journey.overlap_ratio <= MAX_OVERLAP_RATIO
  end

  def rank(journey)
    return [0, journey.overlap_ratio] if right_length?(journey)

    [1, journey.overlap_ratio <= MAX_OVERLAP_RATIO ? 0 : 1, length_off(journey)]
  end

  def length_off(journey)
    (journey.estimated_duration_seconds.fdiv(@target_seconds) - 1).abs
  end

  def right_length?(journey)
    return true unless @target_seconds

    length_off(journey) <= @tolerance
  end
end
