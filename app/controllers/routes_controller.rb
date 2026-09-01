class RoutesController < ApplicationController
  before_action :authenticate_user!

  def create
    if current_user.current_latitude.blank? || current_user.current_longitude.blank?
      return redirect_to root_path, alert: "Set your location first"
    end

    result = RouteBuilder.new(
      lat: current_user.current_latitude,
      lng: current_user.current_longitude,
      theme_key: params[:theme_key]
    ).call

    if result.success?
      current_user.pending_journeys.destroy_all
      journey = result.journey
      @pending_journey = current_user.pending_journeys.create!(
        name: journey.name,
        description: journey.description,
        theme_key: journey.theme_key,
        encoded_polyline: journey.encoded_polyline,
        distance_meters: journey.distance_meters,
        estimated_duration_seconds: journey.estimated_duration_seconds,
        lat: journey.start_point.y,
        lng: journey.start_point.x
      )
    else
      @error = result.error
    end
  end

  def save
    pending = current_user.pending_journeys.order(created_at: :desc).first
    return redirect_to root_path, alert: "No route to save" if pending.nil?

    journey = Journey.create!(pending.to_journey_attributes)
    pending.destroy

    if params[:start].present?
      redirect_to new_journey_walk_path(journey)
    else
      redirect_to root_path, notice: "Route saved"
    end
  end

  def destroy
    current_user.pending_journeys.destroy_all
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
