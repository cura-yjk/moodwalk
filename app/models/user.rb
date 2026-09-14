class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :walks
  has_many :saved_journeys, dependent: :destroy
  has_many :saved_routes, through: :saved_journeys, source: :journey

  validates :name, presence: true

  # How many places to keep for one-tap switching. Small on purpose: this is a
  # shortcut back to the two or three places someone actually walks from, not
  # a location history.
  MAX_RECENT_LOCATIONS = 4

  # Two places within this distance are the same place, so a slightly different
  # GPS fix doesn't fill the list with near-duplicates of where you're standing.
  SAME_PLACE_METERS = 200

  # Moves the user to a place and remembers where they were, most recent first.
  #
  # `manual` records that this place was chosen rather than detected, which is
  # what stops automatic detection overwriting it on the next page load.
  def move_to!(latitude:, longitude:, name:, manual: false)
    remember_current_location
    update!(current_latitude: latitude, current_longitude: longitude,
            current_location_name: name, location_manually_set: manual)
  end

  def recent_locations_list
    Array(recent_locations).map { |entry| entry.to_h.symbolize_keys }
  end

  private

  def remember_current_location
    return if current_latitude.blank? || current_longitude.blank? || current_location_name.blank?

    entry = { name: current_location_name, lat: current_latitude, lng: current_longitude }
    kept = recent_locations_list.reject { |other| same_place?(entry, other) }

    self.recent_locations = ([entry] + kept).first(MAX_RECENT_LOCATIONS)
  end

  def same_place?(entry, other)
    return true if entry[:name] == other[:name]

    GeoDistance.haversine(entry[:lat], entry[:lng], other[:lat].to_f, other[:lng].to_f) < SAME_PLACE_METERS
  end
end
