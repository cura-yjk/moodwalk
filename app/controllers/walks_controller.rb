class WalksController < ApplicationController
  def new
    @journey = Journey.find(params[:journey_id])
  end

  def create
    @journey = Journey.find(params[:journey_id])
    @walk = @journey.walks.new(user: current_user, started_at: Time.current)

    if @walk.save
      redirect_to walk_path(@walk)
    else
      redirect_to new_journey_walk_path(@journey), alert: "Couldn't start walk"
    end
  end

  def show
    @walk = current_user.walks.find(params[:id])
    @journey = @walk.journey
  end

  # placeholder index edit update complete tbc
  def index
    @walks = current_user.walks
  end

  def edit
    @walk = current_user.walks.find(params[:id])
  end

  def update
    @walk = current_user.walks.find(params[:id])
    @walk.update(walk_params)
    redirect_to walk_path(@walk)
  end

  def complete
    @walk = current_user.walks.find(params[:id])
    @walk.update(completed_at: Time.current)
    redirect_to walk_path(@walk)
  end

  private

  def walk_params
    params.require(:walk).permit(:mood_after, :reflection)
  end
end
