# app/controllers/journeys_controller.rb
#
# The missing entry point in the pipeline: user taps a theme -> this runs
# RouteBuilder -> a Journey exists -> redirect into the existing
# new_journey_walk_path flow (WalksController#new already expects
# Journey.find(params[:journey_id]) to succeed).
class JourneysController < ApplicationController
  before_action :authenticate_user!

  def create
    return redirect_to root_path, alert: "Pick a theme to get started." unless THEMES.key?(theme_key)

    unless current_user.current_latitude && current_user.current_longitude
      return redirect_to root_path, alert: "We need your location to find a walk nearby."
    end

    result = RouteBuilder.new(
      lat: current_user.current_latitude,
      lng: current_user.current_longitude,
      theme_key: theme_key
    ).call

    if result.success?
      redirect_to new_journey_walk_path(result.journey)
    else
      # PoiFinder/LlmPoiCurator/JourneyGenerator can each fail independently
      # (no nearby places, LLM picked nothing valid, no route found) -
      # result.error carries whichever one it was.
      redirect_to root_path, alert: result.error
    end
  end

  def save
    @journey = Journey.find(params[:id])
    @journey.update(saved: true)
    redirect_to walks_path, notice: "Route saved"
  end

  private

  # Only ever comes from the theme buttons on the homepage (not a real
  # form), same pattern as WalksController's sanitized_mood_before - so
  # validate against the known theme set rather than trusting it outright.
  def theme_key
    params[:theme_key].to_s.to_sym
  end
end
