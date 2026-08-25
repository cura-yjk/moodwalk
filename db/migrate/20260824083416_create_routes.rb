class CreateRoutes < ActiveRecord::Migration[8.1]
  def change
    enable_extension 'postgis' unless extension_enabled?('postgis')

    create_table :routes do |t|
      t.text :encoded_polyline, null: false
      t.st_point :start_point, geographic: true, null: false  # PostGIS geography(Point,4326)
      t.decimal :distance_meters
      t.integer :estimated_duration_seconds
      t.string :name
      t.text :description
      t.integer :estimated_steps
      t.timestamps
    end

    add_index :routes, :start_point, using: :gist
  end
end
