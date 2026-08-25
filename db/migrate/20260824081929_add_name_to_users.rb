class AddNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :current_longitude, :float
    add_column :users, :current_latitude, :float
  end
end
