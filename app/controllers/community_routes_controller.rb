class CommunityRoutesController < ApplicationController
  def index
    @journeys = Journey.community.newest_first.includes(walks: { photo_attachment: :blob })
  end

  def show
    @journey = Journey.community.find(params[:id])
    @recent_photos = @journey.community_photos(limit: 6)
    @journey_saved = @journey.saved_by?(current_user)
  end
end
