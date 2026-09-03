class AddLocationNameToJourneys < ActiveRecord::Migration[8.1]
  def change
    add_column :journeys, :location_name, :string
  end
end
