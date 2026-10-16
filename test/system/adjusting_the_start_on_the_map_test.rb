require "application_system_test_case"

# A picked search result is a name's centre point, so it opens on a map with a
# fixed pin, to be moved to where the walk really starts. The spot under the
# pin is named by GET /location/reverse -- a Mapbox call from the server -- so
# these count what reached Mapbox's reverse geocoder, not only what the label
# says.
#
# Selenium can't drag a WebGL canvas reliably, so a move is the map's own
# jumpTo, carrying an originalEvent the way a drag or a key press does: that is
# how the controller tells the user's moves from its own jump to a result.
class AdjustingTheStartOnTheMapTest < ApplicationSystemTestCase
  FORWARD_GEOCODE = %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward}
  REVERSE_GEOCODE = %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse}

  PICKED = { lat: 35.66, lng: 139.70 }.freeze
  # About 700m from the picked result: well past the 25m that keeps its name.
  MOVED = { lat: 35.665, lng: 139.705 }.freeze

  STARTED = /Starting from Higashikasai\s*· pinned/

  # The controller waits for the map to have been still for 3 seconds.
  PAST_SETTLE = 4.5

  setup do
    stub_request(:get, FORWARD_GEOCODE)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "features" => [{ "geometry" => { "coordinates" => [PICKED[:lng], PICKED[:lat]] },
                         "properties" => { "name" => "Shibuya", "place_formatted" => "Tokyo, Japan" } }]
      }.to_json)
    stub_request(:get, REVERSE_GEOCODE)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "features" => [{ "properties" => { "name" => "Higashikasai" } }] }.to_json)

    sign_in_as users(:walker)
    wait_for_controller(".location-bar", "location-entry")
    click_until(".location-bar-change", appears: "#location-query")
    pick_result("Shibuya")
  end

  test "a picked place opens on the map under its own name" do
    assert_selector ".location-adjust-label", text: "Starting from Shibuya"

    sleep PAST_SETTLE
    assert_not_requested :get, REVERSE_GEOCODE
  end

  # One session made 71 lookups in 24 seconds, one per move, before the wait.
  test "moving the map names the spot once, after it has been still" do
    move_map_to(lat: 35.662, lng: 139.702)
    assert_selector ".location-adjust-label", text: "Stop moving the map to see where this is"
    move_map_to(lat: 35.664, lng: 139.704)
    move_map_to(**MOVED)

    assert_selector ".location-adjust-label", text: "Starting from near Higashikasai", wait: PAST_SETTLE
    assert_requested :get, REVERSE_GEOCODE, times: 1
    assert_requested(:get, REVERSE_GEOCODE) { |request| at?(request, MOVED) }
  end

  # The label is a neighbourhood, which a few steps don't change.
  test "a nudge of a few metres keeps the picked name without a lookup" do
    move_map_to(lat: PICKED[:lat] + 0.0001, lng: PICKED[:lng])

    assert_selector ".location-adjust-label", text: "Starting from Shibuya", wait: PAST_SETTLE
    assert_not_requested :get, REVERSE_GEOCODE
  end

  test "starting here sets the spot on the map, under the name already shown" do
    move_map_to(**MOVED)
    assert_selector ".location-adjust-label", text: "near Higashikasai", wait: PAST_SETTLE

    start_here

    assert_moved_to_higashikasai
    # The name came from the browser, so the server didn't look it up again.
    assert_requested :get, REVERSE_GEOCODE, times: 1
  end

  # The label still describes where the pin was, so the server names the spot.
  test "starting here before the map settles still names the new spot" do
    move_map_to(**MOVED)
    assert_selector ".location-adjust-label", text: "Stop moving the map"

    start_here

    assert_moved_to_higashikasai
  end

  test "back closes the map without moving anything" do
    before = users(:walker).current_location_name

    # click_until waits for something to appear; this waits for it to go.
    attempt_click(".location-adjust-back")
    attempt_click(".location-adjust-back", via_dom: true) unless has_no_selector?(".location-adjust", wait: 3)
    assert_no_selector ".location-adjust"

    assert_equal before, users(:walker).reload.current_location_name
  end

  private

  # Sets the field through the DOM: headless Chrome here sometimes drops
  # keystrokes (see SearchingForAStartTest#type_query).
  def pick_result(query)
    page.execute_script(<<~JS, find("#location-query"), query)
      const [field, query] = arguments
      field.value = query
      field.dispatchEvent(new InputEvent("input", { bubbles: true, data: query }))
    JS
    click_until(".location-result", appears: ".location-adjust")
    wait_for_map
  end

  def wait_for_map
    Timeout.timeout(10) { sleep 0.05 until page.evaluate_script("!!#{controller_js}.map") }
  rescue Timeout::Error
    flunk "the map never loaded"
  end

  def move_map_to(lat:, lng:)
    page.execute_script(<<~JS, lat, lng)
      const [lat, lng] = arguments
      #{controller_js}.map.jumpTo({ center: [lng, lat] }, { originalEvent: new MouseEvent("mouseup") })
    JS
  end

  def controller_js
    "window.Stimulus.getControllerForElementAndIdentifier(" \
      "document.querySelector('.location-bar'), 'location-entry')"
  end

  def at?(request, point)
    params = Rack::Utils.parse_query(URI(request.uri).query)
    (params["latitude"].to_f - point[:lat]).abs < 0.0001 && (params["longitude"].to_f - point[:lng]).abs < 0.0001
  end

  # Saving reloads the page, and Capybara can go looking for <html> while the
  # old one is gone -- which only happens because the click landed.
  def start_here
    click_and_confirm("Start here", expect: STARTED)
  rescue Capybara::ElementNotFound
    assert_text STARTED, wait: 5
  end

  def assert_moved_to_higashikasai
    user = users(:walker).reload
    assert_equal "Higashikasai", user.current_location_name
    assert user.location_manually_set
    assert_in_delta MOVED[:lat], user.current_latitude, 0.0001
    assert_in_delta MOVED[:lng], user.current_longitude, 0.0001
  end
end
