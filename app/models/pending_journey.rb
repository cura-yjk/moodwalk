class PendingJourney < ApplicationRecord
  belongs_to :user

  before_validation :set_expiration, on: :create

  def to_journey_attributes
    {
      name: name,
      description: description,
      theme_key: theme_key,
      encoded_polyline: encoded_polyline,
      distance_meters: distance_meters,
      estimated_duration_seconds: estimated_duration_seconds,
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(lng, lat)
    }
  end

  private

  def set_expiration
    self.expires_at ||= 24.hours.from_now
  end
end
