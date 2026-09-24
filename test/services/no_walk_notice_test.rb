require "test_helper"

# The notices' wording is exercised end to end in JourneysControllerTest,
# along with which themes get suggested. These pin the sentences that need no
# Google search to reach.
class NoWalkNoticeTest < ActiveSupport::TestCase
  test "an outage says so, and suggests nothing that couldn't work either" do
    assert_equal "We couldn't reach our map services just now. Please try again in a moment.",
                 NoWalkNotice::UNAVAILABLE
  end

  test "names a theme's places in its own words, with the time picked" do
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { "places" => [] }.to_json)
    notice = NoWalkNotice.new(theme_key: :refresh, duration_minutes: 10, lat: 35.70, lng: 139.80)

    assert_equal "No scenic spots within a 10-minute walk from here. Try a longer walk, or No rush.",
                 notice.nothing_nearby
  end
end
