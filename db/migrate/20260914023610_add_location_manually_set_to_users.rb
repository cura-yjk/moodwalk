class AddLocationManuallySetToUsers < ActiveRecord::Migration[8.1]
  def change
    # Whether the current location was chosen deliberately rather than detected.
    #
    # Without this, automatic detection cannot tell a place you picked from a
    # stale fix, so it "corrects" your choice back to wherever you are standing
    # on the next page load. Picking a place sets this; "Use my current
    # location" clears it, which is how you go back to being tracked.
    add_column :users, :location_manually_set, :boolean, default: false, null: false
  end
end
