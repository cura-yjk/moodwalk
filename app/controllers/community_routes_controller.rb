class CommunityRoutesController < ApplicationController
  def index
    @journeys = Journey.community.includes(walks: { photo_attachment: :blob })
  end

  def show
    @journey = Journey.community.find(params[:id])
    @recent_photos = @journey.community_photos(limit: 6)
  end
end
