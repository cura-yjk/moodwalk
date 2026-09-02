class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:home]

  SUGGESTION_COUNT = 3

  def home
    @journeys = user_signed_in? ? nearby_journeys : []
  end

  private

  # The nearest *recommendable* community routes near the user -- a Journey only
  # counts as "community" once someone has bookmarked it or walked it
  # (see JourneysController#save and WalksController#create). Freshly
  # generated-but-untouched journeys stay out of this list.
  def nearby_journeys
    lat = current_user.current_latitude
    lng = current_user.current_longitude
    return Journey.none unless lat && lng

    Journey.near(lat, lng).where(recommendable: true, theme_key: nil).limit(SUGGESTION_COUNT)
  end
end
