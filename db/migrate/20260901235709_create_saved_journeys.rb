class CreateSavedJourneys < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_journeys do |t|
      t.references :user, null: false, foreign_key: true
      t.references :journey, null: false, foreign_key: true

      t.timestamps
    end
    add_index :saved_journeys, [:user_id, :journey_id], unique: true
  end
end
