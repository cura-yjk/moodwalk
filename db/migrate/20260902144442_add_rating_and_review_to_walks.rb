class AddRatingAndReviewToWalks < ActiveRecord::Migration[8.1]
  def change
    add_column :walks, :rating, :integer
    add_column :walks, :review, :text
  end
end
