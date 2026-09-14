# Writes a route's real, LLM-written description after the fact.
#
# RouteBuilder saves every journey with a plain-Ruby fallback description, so a
# route is never without one; this replaces it with the better text once the
# LLM answers. It runs off the request because the LLM was two thirds of a
# route's generation time (~3s of a ~4.5s build, measured), and nothing in the
# route depends on its output -- the journey is fully built before this runs.
class JourneyDescriptionJob < ApplicationJob
  queue_as :default

  # The journey can be gone by the time this runs.
  discard_on ActiveJob::DeserializationError

  def perform(journey, waypoints)
    return if journey.theme_key.blank?

    result = describe(journey, waypoints)
    return journey.update(description: result.description) if result.success?

    # Not retried: the fallback is already in place and readable, so a missing
    # description is cosmetic rather than a failure to recover from.
    Rails.logger.warn("JourneyDescriptionJob: keeping fallback for journey #{journey.id} (#{result.error})")
  end

  private

  def describe(journey, waypoints)
    RouteDescriber.new(
      theme_key: journey.theme_key,
      waypoints: Array(waypoints).map { |wp| wp.to_h.symbolize_keys },
      target_distance_meters: journey.distance_meters
    ).call
  end
end
