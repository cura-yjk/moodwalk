# app/controllers/journeys_controller.rb
#
# Entry point for the theme picker: user taps a theme -> this runs
# RouteBuilder -> the generated Journey is saved (unsaved/"unbookmarked" by
# default) -> redirect into the existing new_journey_walk_path flow
# (WalksController#new already expects Journey.find(params[:journey_id]) to
# succeed).
class JourneysController < ApplicationController
  before_action :authenticate_user!

  def create
    return redirect_to root_path, alert: "Pick a theme to get started." unless THEMES.key?(theme_key)
    return redirect_to root_path, alert: "We need your location to find a walk nearby." unless located?

    result = generate_journey
    if result.error
      redirect_to new_journey_walk_path(fallback_journey)
    else
      result.journey.save
      redirect_to new_journey_walk_path(result.journey)
    end
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

  private

  # When generation fails, prefer a saved journey tagged with the same theme and (if a duration
  # was picked) within RouteBuilder's own tolerance of the target duration, falling back further
  # to any saved journey, then any journey at all.
  def fallback_journey
    themed = Journey.near(current_user.current_latitude, current_user.current_longitude)
                    .where(recommendable: true, theme_key: theme_key.to_s)

    if duration_minutes.present?
      themed = themed.where(estimated_duration_seconds: duration_range)
    else
      themed = themed.order(estimated_duration_seconds: :desc)
    end

    themed.first ||
      Journey.near(current_user.current_latitude, current_user.current_longitude).find_by(recommendable: true) ||
      Journey.last
  end

  def duration_range
    target_seconds = duration_minutes * 60
    lower = (target_seconds * (1 - RouteBuilder::TOLERANCE_RATIO)).round
    upper = (target_seconds * (1 + RouteBuilder::TOLERANCE_RATIO)).round
    lower..upper
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

  # PoiFinder/LlmPoiCurator/JourneyGenerator can each fail independently
  # (no nearby places, LLM picked nothing valid, no route found) -
  # result.error carries whichever one it was.
  def generate_journey
    RouteBuilder.new(
      lat: current_user.current_latitude,
      lng: current_user.current_longitude,
      theme_key: theme_key,
      duration_minutes: duration_minutes
    ).call
  end

  # Comes from the duration bottom sheet's hidden field - blank for "No
  # rush", so RouteBuilder falls back to its default search radius.
  def duration_minutes
    Integer(params[:duration_minutes], exception: false)
  end
end
