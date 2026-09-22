require "test_helper"

# Every generated route used to be named after its theme -- four names across
# the whole app. In production 85 journeys of 107 were called Calm, Refresh,
# Cheerful or Recharge.
class JourneyTitleTest < ActiveSupport::TestCase
  test "names a route after where it is, what it leads with, and its shape" do
    assert_equal "Meguro Garden Loop", title(place: "Meguro", categories: ["botanical_garden"])
  end

  test "a one-way route is a walk rather than a loop" do
    assert_equal "Meguro Garden Walk",
                 title(place: "Meguro", categories: ["botanical_garden"], round_trip: false)
  end

  test "leads with the first waypoint, which is the first place reached" do
    assert_equal "Meguro Bakery Loop", title(place: "Meguro", categories: %w[bakery park])
    assert_equal "Meguro Park Loop", title(place: "Meguro", categories: %w[park bakery])
  end

  test "skips a waypoint whose category has no word for a title" do
    assert_equal "Meguro Market Loop", title(place: "Meguro", categories: %w[not_a_real_type market])
  end

  # location_name falls back to "Nearby" for a point that could not be geocoded,
  # and "Nearby Park Loop" is not a place anyone has been.
  test "drops the placeholder neighbourhood rather than naming a walk after it" do
    assert_equal "Park Loop", title(place: Journey::FALLBACK_LOCATION_NAME, categories: ["park"])
    assert_equal "Park Loop", title(place: nil, categories: ["park"])
  end

  test "still names a route with nothing recognisable on it" do
    assert_equal "Meguro Loop", title(place: "Meguro", categories: ["not_a_real_type"])
    assert_equal "Meguro Walk", title(place: "Meguro", categories: [], round_trip: false)
  end

  # With no place and no feature, the theme is the only thing left that says
  # anything -- which is where this started, but only as the last resort.
  test "falls back to the theme when there is neither a place nor a feature" do
    assert_equal "Calm Loop", title(place: nil, categories: [], theme_key: :calm)
    assert_equal "Walk", title(place: nil, categories: [], theme_key: nil, round_trip: false)
  end

  test "never repeats the duration, which every card already shows beside it" do
    assert_no_match(/min|hour/, title(place: "Meguro", categories: ["park"]))
  end

  # A category added to a theme without a word here silently drops out of every
  # title it should have shaped.
  test "every category a theme can select has a word for a title" do
    THEMES.each do |theme, config|
      config[:categories].each do |category|
        assert JourneyTitle::FEATURE_WORDS.key?(category),
               "#{theme}'s #{category} has no entry in FEATURE_WORDS"
      end
    end
  end

  test "the words are short enough to sit on a card" do
    JourneyTitle::FEATURE_WORDS.each_value do |word|
      assert_operator word.length, :<=, 10, "#{word} is long for a card title"
    end
  end

  private

  def title(place:, categories:, round_trip: true, theme_key: :calm)
    JourneyTitle.new(
      location_name: place,
      waypoints: categories.map { |c| { category: c } },
      round_trip: round_trip,
      theme_key: theme_key
    ).call
  end
end
