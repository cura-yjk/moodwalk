class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:home]

  def home
    @journeys = user_signed_in? ? nearby_journeys : Journey.none
  end

  private

  # Journey.near (see app/models/journey.rb) does the actual PostGIS
  # distance query. If some themes aren't represented nearby yet, generate
  # them now via RouteBuilder so the homepage never shows fewer than the
  # full theme set when a route exists for it. Themes RouteBuilder can't
  # find anything for (no nearby POIs, etc.) just don't produce a card --
  # nothing to surface mid-page-load if one theme comes up empty.
  def nearby_journeys
    lat = current_user.current_latitude
    lng = current_user.current_longitude
    return Journey.none unless lat && lng

    existing = Journey.near(lat, lng)
    return existing if existing.size >= THEMES.size

    generate_missing_themes(lat, lng, existing)
    Journey.near(lat, lng)
  end

  def generate_missing_themes(lat, lng, existing)
    covered = existing.map(&:theme_key).compact
    missing = THEMES.keys.map(&:to_s) - covered

    missing.each do |theme_key|
      RouteBuilder.new(lat: lat, lng: lng, theme_key: theme_key).call
    end
  end
end
