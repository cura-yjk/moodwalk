class CreateWalks < ActiveRecord::Migration[8.1]
  def change
    create_table :walks do |t|
      t.datetime :started_at
      t.datetime :completed_at
      t.decimal :actual_distance
      t.integer :actual_steps
      t.text :reflection
      t.string :mood_after
      t.references :user, null: false, foreign_key: true
      t.references :route, null: false, foreign_key: true

      t.timestamps
    end
  end
end
