class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:home]

  def home
    @journeys = user_signed_in? ? nearby_journeys : Journey.none
  end

  private

  # Backfills any theme with no nearby journey yet via RouteBuilder, so the
  # homepage never shows fewer than the full theme set once routes exist.
  def nearby_journeys
    lat = current_user.current_latitude
    lng = current_user.current_longitude
    return Journey.none unless lat && lng

    existing = Journey.near(lat, lng)
    covered_themes = existing.map(&:theme_key).compact.uniq
    return existing if covered_themes.size >= THEMES.size

    generate_missing_themes(lat, lng, covered_themes)
    Journey.near(lat, lng)
  end

  def generate_missing_themes(lat, lng, covered_themes)
    missing = THEMES.keys.map(&:to_s) - covered_themes

    missing.each do |theme_key|
      RouteBuilder.new(lat: lat, lng: lng, theme_key: theme_key).call
    end
  end
end
