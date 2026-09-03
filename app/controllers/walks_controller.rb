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
    @alternate_journey = @journey.alternate
    @journey_saved = current_user.saved_journeys.exists?(journey: @journey)
  end

  def create
    @journey = Journey.find(params[:journey_id])
    @walk = @journey.walks.new(user: current_user, started_at: Time.current, mood_before: sanitized_mood_before)

    if @walk.save
      @journey.update(recommendable: true)
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
    if params[:filter] == "saved"
      @saved_journeys = current_user.saved_routes
    else
      @walks = current_user.walks.includes(:journey, photo_attachment: :blob).order(started_at: :desc)
      @grouped_walks = group_walks_by_date(@walks)
      @stats = Walk.lifetime_stats(@walks)
      @map_center = exploration_map_center(@walks)
      @map_routes = @walks.map { |walk| walk.journey.route_coordinates }.uniq
      @map_photo_points = exploration_photo_points(@walks)
    end
  end

  def edit
    @walk = current_user.walks.find(params[:id])
    @journey_saved = current_user.saved_journeys.exists?(journey: @walk.journey)
  end

  def update
    @walk = current_user.walks.find(params[:id])
    if @walk.update(walk_params)
      redirect_to memory_walk_path(@walk)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def memory
    @walk = current_user.walks.find(params[:id])
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

  def share
    @walk = current_user.walks.find(params[:id])
    @walk.share!(share_params)
    render json: { shared: true }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def share_quote
    walk = Walk.find(params[:id])

    # Generated once per walk and persisted -- the LLM isn't deterministic,
    # so without this, revisiting the memory page would show a different
    # quote each time instead of the one first generated for this walk.
    return render json: { quote: walk.share_quote } if walk.share_quote.present?

    generate_and_render_quote(walk)
  end

  private

  def generate_and_render_quote(walk)
    result = ShareQuoteGenerator.new(
      reflection: params[:reflection],
      mood_before: walk.mood_before,
      mood_after: params[:mood_after]
    ).call

    if result.success?
      walk.update(share_quote: result.quote)
      render json: { quote: result.quote }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  def walk_params
    params.require(:walk).permit(:mood_after, :reflection, :photo, :photo_latitude, :photo_longitude)
  end

  def share_params
    attrs = params.permit(:rating, :review)
    attrs[:rating] = attrs[:rating].presence
    attrs
  end

  # The "Start walking" form carries along whatever mood the user last
  # picked in the homepage check-in (see mood_checkin_controller.js), as a
  # plain hidden field -- not a real form the user fills in, so validate it
  # against the known mood set rather than trusting it outright.
  def sanitized_mood_before
    mood = params.dig(:walk, :mood_before)
    mood if ApplicationHelper::MOOD_ICONS.key?(mood)
  end

  # Centers the walks#index exploration map on the user's current location
  # when we have one, falling back to the most recent walk's journey so the
  # map still lands somewhere sensible for users without a stored location.
  def exploration_map_center(walks)
    if current_user.current_longitude && current_user.current_latitude
      [current_user.current_longitude, current_user.current_latitude]
    else
      walks.first&.journey&.start_coordinates
    end
  end

  def exploration_photo_points(walks)
    walks.select { |walk| walk.photo.attached? }.map do |walk|
      lng, lat = walk.photo_coordinates
      { lng: lng, lat: lat, photo_url: url_for(walk.photo) }
    end
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
