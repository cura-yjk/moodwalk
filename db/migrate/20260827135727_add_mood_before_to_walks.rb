class AddMoodBeforeToWalks < ActiveRecord::Migration[8.1]
  def change
    add_column :walks, :mood_before, :string
  end
end
