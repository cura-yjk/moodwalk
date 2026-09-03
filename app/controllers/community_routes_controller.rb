class CommunityRoutesController < ApplicationController
  def index
    @journeys = Journey.community.newest_first.includes(walks: { photo_attachment: :blob })
  end

  def show
    @journey = Journey.community.find(params[:id])
    @recent_photos = @journey.community_photos(limit: 6)
    @journey_saved = current_user.saved_journeys.exists?(journey: @journey)
  end
end
