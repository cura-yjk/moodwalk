# app/controllers/journeys_controller.rb
#
# Entry point for the theme picker: user taps a theme -> this runs
# RouteBuilder -> the generated Journey is saved (unsaved/"unbookmarked" by
# default) -> redirect into the existing new_journey_walk_path flow
# (WalksController#new already expects Journey.find(params[:journey_id]) to
# succeed).
class JourneysController < ApplicationController
  before_action :authenticate_user!

  # The durations the theme picker offers (pages/_theme_picker), longest last
  # - the "nothing nearby" message only suggests a longer walk if there is one.
  DURATION_CHOICES = [10, 20, 30].freeze

  def create
    return redirect_to root_path, alert: "Pick a theme to get started." unless THEMES.key?(theme_key)
    return redirect_to root_path, alert: "We need your location to find a walk nearby." unless located?
    return redirect_to root_path, alert: "Pick how long you have to get started." unless offered_duration?

    result = generate_journey
    return redirect_to new_journey_walk_path(persist(result)) if result.success?

    # A saved walk only needs the database, so it's offered even when Google
    # can't be reached.
    fallback = fallback_journey
    return redirect_to new_journey_walk_path(fallback) if fallback

    redirect_to root_path, notice: result.unavailable ? NoWalkNotice::UNAVAILABLE : no_walk_notice.nothing_nearby
  end

  # Toggles the saved state: creates the SavedJourney if it doesn't exist yet,
  # destroys it if it does. The button on the other end treats this endpoint
  # as a toggle, not a one-way "save".
  def save
    @journey = Journey.find(params[:id])
    saved_journey = current_user.saved_journeys.find_by(journey: @journey)
    saved_journey ? saved_journey.destroy! : current_user.saved_journeys.create!(journey: @journey)
    render json: { saved: saved_journey.nil? }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Answers straight away, with the best highlights available right now.
  #
  # This used to generate them inline, so the first view of a journey held the
  # request open on a live LLM call -- about twelve seconds, with an empty list
  # on screen for all of it. Twenty of the journeys in production have never
  # been viewed, so twenty people would have waited.
  #
  # Now the fallback goes out immediately and the real ones are written in the
  # background. `pending` tells the page whether to look again.
  def highlights
    @journey = Journey.find(params[:id])

    return render json: { highlights: @journey.highlights_text, pending: false } if @journey.highlights_text.present?

    # Polling must not queue more work: without this, a page checking every few
    # seconds would enqueue a generation every few seconds.
    JourneyHighlightsJob.perform_later(@journey) if params[:poll].blank?

    render json: { highlights: @journey.highlights, pending: true }
  end

  private

  # Saves the generated route, unless we already have it.
  #
  # Selection is deterministic for a given set of candidates, so the same
  # doorstep can produce a route that already exists -- another user's, or
  # this user's, from before. Production reached 41 journeys holding 35
  # distinct polylines that way. An identical polyline is the same walk, so
  # hand back the row we have: it may already carry a written description and
  # highlights, which a fresh copy would have to generate again.
  def persist(result)
    existing = Journey.find_by(
      encoded_polyline: result.journey.encoded_polyline, theme_key: result.journey.theme_key
    )
    return existing if existing

    result.journey.save
    enqueue_description(result) if result.journey.persisted?
    result.journey
  end

  # Counts upward for the length of a session, so each tap of the same theme
  # offers the next route in PoiSelector's shortlist instead of the one just
  # turned down. Deliberately not random: two taps in a row must not be able
  # to land on the same walk, which is the whole complaint.
  def variety_seed
    session[:variety_seed] = session[:variety_seed].to_i + 1
  end

  # When no route can be built, a saved one that answers the same request -
  # see ReusableWalk. It used to reach 3km for a start, consider only
  # curated routes, and then settle for any theme or the newest route in the
  # database: a silent swap for something the user didn't ask for, possibly in
  # another city. Nil now means there's no such walk, and the user is told so.
  def fallback_journey
    ReusableWalk.find(current_user.current_latitude, current_user.current_longitude,
                      theme_key: theme_key, duration_minutes: duration_minutes)
  end

  def no_walk_notice
    NoWalkNotice.new(theme_key: theme_key, duration_minutes: duration_minutes,
                     lat: current_user.current_latitude, lng: current_user.current_longitude)
  end

  # Only ever comes from the homepage's duration sheet (a hidden field set
  # by JS, not free text), same pattern as WalksController's
  # sanitized_mood_before - so validate against the known theme set rather
  # than trusting it outright. Memoized so "surprise_me" resolves to one
  # random theme per request, not a different one each time this is called.
  def theme_key
    @theme_key ||= begin
      key = params[:theme_key].to_s
      key = THEMES.keys.sample.to_s if key == "surprise_me"
      key.to_sym
    end
  end

  def located?
    current_user.current_latitude && current_user.current_longitude
  end

  # Swaps in the LLM-written description without making the user wait for it.
  #
  # Never fatal. The journey is already saved and already carries a readable
  # fallback description, so a queue that is unavailable costs a nicer sentence
  # -- not the walk. Taking the LLM off the request was pointless if the
  # *enqueue* could still fail the request, which is exactly what happened in
  # production when Solid Queue's tables turned out to be missing.
  def enqueue_description(result)
    JourneyDescriptionJob.perform_later(result.journey, result.waypoints)
  rescue StandardError => e
    Rails.logger.error(
      "Could not enqueue JourneyDescriptionJob for journey #{result.journey.id}: #{e.class}: #{e.message}"
    )
  end

  # PoiFinder/PoiSelector/RouteDescriber/JourneyGenerator can each fail
  # independently (no nearby places, no viable waypoint combination, LLM
  # description failed, no route found) - result.error carries whichever one it was.
  def generate_journey
    RouteBuilder.new(
      lat: current_user.current_latitude,
      lng: current_user.current_longitude,
      theme_key: theme_key,
      duration_minutes: duration_minutes,
      variety_seed: variety_seed
    ).call
  end

  # Comes from the duration bottom sheet's hidden field - blank for "No
  # rush", so RouteBuilder falls back to its default search radius.
  def duration_minutes
    Integer(params[:duration_minutes], exception: false)
  end

  # Blank is "No rush". Anything else must be a duration the picker offers:
  # 0 or less used to reach RouteBuilder as a zero search radius and a
  # division by zero, and fail silently behind a "0-minute walk" banner.
  def offered_duration?
    params[:duration_minutes].blank? || DURATION_CHOICES.include?(duration_minutes)
  end
end
