class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :walks
  has_many :saved_journeys, dependent: :destroy
  has_many :saved_routes, through: :saved_journeys, source: :journey

  validates :name, presence: true
end
