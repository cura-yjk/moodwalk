class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:home]

  SUGGESTION_RADIUS_METERS = 250

  def home
    @journeys = user_signed_in? ? nearby_journeys.to_a.sample(3) : []
  end

  private

  def nearby_journeys
    lat = current_user.current_latitude
    lng = current_user.current_longitude
    return Journey.none unless lat && lng

    existing = Journey.near(lat, lng, SUGGESTION_RADIUS_METERS).where.missing(:walks)
    covered_themes = existing.map(&:theme_key).compact.uniq
    return existing if covered_themes.size >= THEMES.size

    generate_missing_themes(lat, lng, covered_themes)
    Journey.near(lat, lng, SUGGESTION_RADIUS_METERS).where.missing(:walks)
  end

  def generate_missing_themes(lat, lng, covered_themes)
    missing = THEMES.keys.map(&:to_s) - covered_themes

    missing.each do |theme_key|
      result = RouteBuilder.new(lat: lat, lng: lng, theme_key: theme_key).call
      result.journey.save! if result.success?
    end
  end
end
