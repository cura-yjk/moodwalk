require "test_helper"

class SavedJourneyTest < ActiveSupport::TestCase
  test "requires both sides of the bookmark" do
    assert_not SavedJourney.new.valid?
  end

  test "a user can only bookmark a journey once" do
    SavedJourney.create!(user: users(:walker), journey: journeys(:meguro_loop))

    assert_raises(ActiveRecord::RecordNotUnique) do
      SavedJourney.create!(user: users(:walker), journey: journeys(:meguro_loop))
    end
  end
end
