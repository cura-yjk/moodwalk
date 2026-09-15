# Writes a journey's LLM-written highlights after the fact.
#
# They used to be generated inside the request that asked for them: opening a
# journey fired an XHR, and that request sat on a live LLM call for around
# twelve seconds while the list on screen stayed empty. Journey#highlights
# already produces a plain-Ruby fallback from the route's categories, so there
# is something true to show immediately and something better to replace it
# with.
class JourneyHighlightsJob < ApplicationJob
  queue_as :default

  # The journey can be gone by the time this runs.
  discard_on ActiveJob::DeserializationError

  def perform(journey)
    # Another view of the same journey may have finished this first; a second
    # LLM call would cost the same and produce the same thing.
    return if journey.highlights_text.present?

    result = JourneyHighlightsGenerator.new(journey: journey).call
    return journey.update(highlights_text: result.highlights) if result.success?

    # Not retried: the fallback is already on screen and accurate, so missing
    # highlights are cosmetic rather than a failure to recover from.
    Rails.logger.warn("JourneyHighlightsJob: keeping fallback for journey #{journey.id} (#{result.error})")
  end
end
