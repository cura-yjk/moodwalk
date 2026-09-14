class AddRecentLocationsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Capped MRU list of places this user has started walks from, so they can
    # switch back with one tap instead of retyping. Small and bounded (see
    # User::MAX_RECENT_LOCATIONS), so it lives here rather than in its own table.
    add_column :users, :recent_locations, :jsonb, default: [], null: false
  end
end
