# app/models/saved_journey.rb
class SavedJourney < ApplicationRecord
  belongs_to :user
  belongs_to :journey
end
