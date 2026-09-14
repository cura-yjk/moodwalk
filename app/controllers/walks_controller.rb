class WalksController < ApplicationController
  def attach_photo
    @walk = current_user.walks.find(params[:id])

    if @walk.update(walk_params)
      head :ok
    else
      render json: { error: @walk.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # Receives a batch of GPS breadcrumbs from walking_controller.js while a walk
  # is in progress. Fire-and-forget from the client's side, so it just needs to
  # persist quickly and return -- the points are stitched into a route later, in
  # Walk#finalize_actual_path! when the walk completes.
  def track
    walk = current_user.walks.find(params[:id])
    rows = WalkTrackPoint.rows_for(walk, breadcrumb_params[:points])

    WalkTrackPoint.insert_all(rows) if rows.any?
    head :no_content
  end

  def new
    @journey = Journey.find(params[:journey_id])
    @alternate_journey = @journey.alternate
    @journey_saved = @journey.saved_by?(current_user)
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
      @stats = Walk.lifetime_stats(@walks)
      @map_routes = @walks.map { |walk| walk.journey.route_coordinates }.uniq
    end
  end

  def edit
    @walk = current_user.walks.find(params[:id])
    @journey_saved = @walk.journey.saved_by?(current_user)
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
    @walk.finalize_actual_path!(
      fallback_distance_km: complete_params[:actual_distance].presence,
      fallback_steps: complete_params[:actual_steps].presence
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
    walk = current_user.walks.find(params[:id])

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

    return render json: { error: result.error }, status: :unprocessable_entity unless result.success?

    walk.update(share_quote: result.quote)
    render json: { quote: result.quote }
  end

  def walk_params
    params.require(:walk).permit(:mood_after, :reflection, :photo, :photo_latitude, :photo_longitude)
  end

  # Breadcrumb batch posted by walking_controller.js#flushBreadcrumbs. `points`
  # is a plain JSON array; each entry carries what the browser's Geolocation
  # API gave us for one fix (see WalkTrackPoint.rows_for).
  def breadcrumb_params
    params.permit(points: %i[latitude longitude accuracy_meters recorded_at])
  end

  # Real distance/steps tracked client-side over the course of the walk (see
  # walking_controller.js#updateTraveledFields). Blank when GPS tracking never
  # ran (e.g. geolocation unsupported, or the dev-only ?arrived= shortcut) --
  # #complete falls back to the journey's planned distance/steps in that case.
  def complete_params
    params.require(:walk).permit(:actual_distance, :actual_steps)
  end

  def share_params
    attrs = params.permit(:rating, :review)
    attrs[:rating] = attrs[:rating].presence
    attrs
  end

  # The "Start walking" form carries along whatever mood the user last
  # picked in the homepage check-in (see mood_checkin_controller.js), as a
  # plain hidden field -- not a real form the user fills in, so drop anything
  # unrecognized here rather than letting it fail the Walk mood validation and
  # block the walk from starting at all.
  def sanitized_mood_before
    mood = params.dig(:walk, :mood_before)
    mood if Walk::MOODS.include?(mood)
  end
end
