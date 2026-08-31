class WalksController < ApplicationController
  def attach_photo
    @walk = current_user.walks.find(params[:id])
    @walk.update(walk_params)
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def new
    @journey = Journey.find(params[:journey_id])
  end

  def create
    @journey = Journey.find(params[:journey_id])
    @walk = @journey.walks.new(user: current_user, started_at: Time.current, mood_before: sanitized_mood_before)

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
    # includes(:journey) avoids an N+1 query — without it, Rails would
    # hit the DB separately for each walk's journey.name in the view
    @walks = current_user.walks.includes(:journey, photo_attachment: :blob).order(started_at: :desc)
    # Group the already-loaded walks into buckets by date.
    # This happens in Ruby (not a second DB query) since @walks is small
    # and already fully loaded — no need to hit the database again.
    @grouped_walks = group_walks_by_date(@walks)
  end

  def edit
    @walk = current_user.walks.find(params[:id])
  end

  def update
    @walk = Walk.find(params[:id])
    # mood_after and reflection are both optional, so update succeeds
    # even if the user submits the form with either field left blank.
    if @walk.update(walk_params)
      redirect_to walks_path, notice: "Walk saved!"
    else
      # Only realistically fails here if something unexpected happens
      # (e.g. a DB-level constraint), since neither field is required.
      render :edit, status: :unprocessable_entity
    end
  end

  def complete
    @walk = current_user.walks.find(params[:id])
    @walk.update(
      completed_at: Time.current,
      actual_steps: 2840,
      actual_distance: 1.9
    )
    redirect_to edit_walk_path(@walk)
  end

  def share_quote
    walk = Walk.find(params[:id])

    result = ShareQuoteGenerator.new(
      reflection: params[:reflection],
      mood_before: walk.mood_before,
      mood_after: params[:mood_after]
    ).call

    if result.success?
      render json: { quote: result.quote }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def walk_params
    params.require(:walk).permit(:mood_after, :reflection, :photo)
  end

  # The "Start walking" form carries along whatever mood the user last
  # picked in the homepage check-in (see mood_checkin_controller.js), as a
  # plain hidden field -- not a real form the user fills in, so validate it
  # against the known mood set rather than trusting it outright.
  def sanitized_mood_before
    mood = params.dig(:walk, :mood_before)
    mood if ApplicationHelper::MOOD_ICONS.key?(mood)
  end

  def group_walks_by_date(walks)
    today = Date.current
    yesterday = today - 1.day
    this_week_range = today.beginning_of_week..today.end_of_week
    last_week_range = (today.beginning_of_week - 1.week)..(today.beginning_of_week - 1.day)

    walks.group_by do |walk|
      walk_date = walk.started_at.to_date

      if walk_date == today
        "Today"
      elsif walk_date == yesterday
        "Yesterday"
      elsif this_week_range.cover?(walk_date)
        "This week"
      elsif last_week_range.cover?(walk_date)
        "Last week"
      else
        # Falls back to a month name for anything older — this single line
        # handles all of history without ever needing a new elsif branch,
        # no matter how far back a walk happened.
        walk_date.strftime("%B %Y") # e.g. "July 2026"
      end
    end
  end
end
