class AddThemeKeyToJourneys < ActiveRecord::Migration[8.1]
  def change
    add_column :journeys, :theme_key, :string
    add_index :journeys, :theme_key
  end
end
