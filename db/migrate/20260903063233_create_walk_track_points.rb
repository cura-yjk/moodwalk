class CreateWalkTrackPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :walk_track_points do |t|
      t.references :walk, null: false, foreign_key: true
      # Raw GPS breadcrumbs streamed from the browser mid-walk. Plain lat/lng
      # decimals (not PostGIS) on purpose -- these are unvalidated sensor
      # readings we never query geospatially; the derived path lives on
      # walks.actual_path as a real geography(LineString) instead.
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.decimal :accuracy_meters
      t.datetime :recorded_at, null: false
      t.timestamps
    end

    add_index :walk_track_points, [:walk_id, :recorded_at]

    # The actual route the user walked, reconstructed from the breadcrumbs above
    # when the walk completes. geography(LineString,4326), mirroring
    # journeys.start_point's type (see db/migrate/20260824083416_create_routes.rb).
    change_table :walks, bulk: true do |t|
      t.line_string :actual_path, geographic: true
    end
  end
end
