class AddShareQuoteToWalks < ActiveRecord::Migration[8.1]
  def change
    add_column :walks, :share_quote, :text
  end
end
