class AddCurrentLocationNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :current_location_name, :string
  end
end
