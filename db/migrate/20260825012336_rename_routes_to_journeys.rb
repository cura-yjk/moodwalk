class RenameRoutesToJourneys < ActiveRecord::Migration[8.1]
  def change
    rename_table :routes, :journeys
    rename_column :walks, :route_id, :journey_id
  end
end
