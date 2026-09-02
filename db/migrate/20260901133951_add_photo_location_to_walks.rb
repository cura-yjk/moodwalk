class AddPhotoLocationToWalks < ActiveRecord::Migration[8.1]
  def change
    add_column :walks, :photo_latitude, :float
    add_column :walks, :photo_longitude, :float
  end
end
