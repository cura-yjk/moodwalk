class PagesController < ApplicationController
  # Skipped only so a signed-out visitor goes to the login form without
  # Devise's "You need to sign in or sign up before continuing." - a warning,
  # for opening the app. Everything on the home page is for a signed-in
  # walker; signed out, it used to render an empty screen.
  skip_before_action :authenticate_user!, only: [:home]

  SUGGESTION_COUNT = 3

  def home
    return redirect_to new_user_session_path unless user_signed_in?

    @journeys = suggested_journeys
  end

  private

  # Recommendable community routes to suggest, nearest first -- a Journey only
  # counts as "community" once someone has bookmarked it or walked it
  # (see JourneysController#save and WalksController#create). Freshly
  # generated-but-untouched journeys stay out of this list.
  #
  # Nearest first, but never *only* nearest. Journey.near searches a 3km radius
  # and the suggestible routes are clustered where they were seeded, so anyone
  # standing further out than that got an empty carousel -- the shelf labelled
  # "Ideas for you, right here" with nothing on it. Somewhere to walk that is a
  # train ride away still reads as an idea; no ideas at all reads as broken.
  def suggested_journeys
    nearby = journeys_within_reach
    return nearby if nearby.size >= SUGGESTION_COUNT

    nearby + further_afield(excluding: nearby)
  end

  def journeys_within_reach
    lat = current_user.current_latitude
    lng = current_user.current_longitude
    return [] unless lat && lng

    suggestible.near(lat, lng).limit(SUGGESTION_COUNT).to_a
  end

  def further_afield(excluding:)
    suggestible.where.not(id: excluding.map(&:id))
               .newest_first
               .limit(SUGGESTION_COUNT - excluding.size)
               .to_a
  end

  def suggestible
    Journey.where(recommendable: true, theme_key: nil)
  end
end
