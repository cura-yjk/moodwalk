class CreatePendingJourneys < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_journeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :theme_key
      t.text :encoded_polyline, null: false
      t.decimal :distance_meters
      t.integer :estimated_duration_seconds
      t.float :lat, null: false
      t.float :lng, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end
  end
end
