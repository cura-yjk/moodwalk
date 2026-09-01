class AddSharedAtToWalks < ActiveRecord::Migration[8.1]
  def change
    add_column :walks, :shared_at, :datetime
    add_index :walks, :shared_at
  end
end
