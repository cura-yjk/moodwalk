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
    return redirect_to root_path, alert: result.error unless result.success?

    result.journey.save!
    redirect_to new_journey_walk_path(result.journey)
  end

  def save
    @journey = Journey.find(params[:id])
    @journey.update(saved: true)
    redirect_to walks_path, notice: "Route saved"
  end

  private

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
