# db/migrate/XXXXXXXXXXXXXX_rename_saved_to_recommendable_on_journeys.rb
class RenameSavedToRecommendableOnJourneys < ActiveRecord::Migration[8.1]
  def change
    rename_column :journeys, :saved, :recommendable
  end
end
