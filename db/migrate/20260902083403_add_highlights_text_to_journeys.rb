class AddHighlightsTextToJourneys < ActiveRecord::Migration[8.1]
  def change
    add_column :journeys, :highlights_text, :jsonb
  end
end
