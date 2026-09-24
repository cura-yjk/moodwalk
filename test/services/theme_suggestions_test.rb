require "test_helper"

class ThemeSuggestionsTest < ActiveSupport::TestCase
  # journeys(:meguro_loop) is a calm walk starting here, 25 minutes long.
  LAT = 35.68
  LNG = 139.77

  test "a saved walk ready nearby is enough, and costs nothing at Google" do
    stub_places(count: 0)

    suggested = suggestions(duration_minutes: 20, excluding: :refresh)

    assert_includes suggested, :calm
    assert_not_requested :post, PoiFinder::NEARBY_SEARCH_URL,
                         body: hash_including("includedPrimaryTypes" => THEMES[:calm][:categories])
  end

  test "never suggests the theme that was just tried" do
    stub_places(count: 5)

    assert_not_includes suggestions(duration_minutes: 20, excluding: :cheerful), :cheerful
  end

  test "stops at LIMIT, busiest themes first" do
    stub_places(count: 5)

    assert_equal %i[calm cheerful], suggestions(duration_minutes: 20, excluding: :recharge)
    assert_requested :post, PoiFinder::NEARBY_SEARCH_URL, times: 1 # calm came free, from the saved walk
  end

  test "searches as far as a walk of that length would" do
    stub_places(count: 0)

    suggestions(duration_minutes: 10, excluding: :calm)

    reach = WalkReach.search_radius(10).round
    assert_requested(:post, PoiFinder::NEARBY_SEARCH_URL, at_least_times: 1) do |request|
      JSON.parse(request.body).dig("locationRestriction", "circle", "radius").round == reach
    end
  end

  private

  def suggestions(duration_minutes:, excluding:)
    ThemeSuggestions.new(lat: LAT, lng: LNG, duration_minutes: duration_minutes, excluding: excluding).call
  end

  def stub_places(count:)
    places = Array.new(count) do |i|
      { "id" => "p#{i}", "displayName" => { "text" => "p#{i}" }, "location" => { "latitude" => LAT, "longitude" => LNG } }
    end
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { "places" => places }.to_json)
  end
end
