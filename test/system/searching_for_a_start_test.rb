require "application_system_test_case"

# Searching for where a walk starts, in the scripts the people using it type:
# Japanese and Chinese place names are often two characters, and both are
# usually typed through an input method that holds Latin letters (romaji,
# pinyin) in the field until the word is converted.
#
# Every search the browser sends is a Mapbox call from the server, so these
# count what reached Mapbox's forward geocoder rather than what the list shows.
class SearchingForAStartTest < ApplicationSystemTestCase
  FORWARD_GEOCODE = %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/forward}

  # Comfortably past the controller's 500ms wait before it searches.
  PAST_DEBOUNCE = 0.9

  setup do
    stub_request(:get, FORWARD_GEOCODE).to_return do |request|
      query = Rack::Utils.parse_query(URI(request.uri).query)["q"]
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { "features" => [suggestion(query)] }.to_json }
    end

    sign_in_as users(:walker)
    wait_for_controller(".location-bar", "location-entry")
    click_until(".location-bar-change", appears: "#location-query")
  end

  test "two Japanese characters are enough to search" do
    type_query("渋谷")

    assert_selector ".location-result", text: "Result for 渋谷"
    assert_requested :get, FORWARD_GEOCODE, query: hash_including("q" => "渋谷")
  end

  test "two Chinese characters are enough to search" do
    type_query("北京")

    assert_selector ".location-result", text: "Result for 北京"
    assert_requested :get, FORWARD_GEOCODE, query: hash_including("q" => "北京")
  end

  test "two Latin letters are not searched, three are" do
    type_query("ma")
    sleep PAST_DEBOUNCE
    assert_not_requested :get, FORWARD_GEOCODE

    type_query("mag")
    assert_selector ".location-result", text: "Result for mag"
  end

  # An input method fires input events while it converts, flagged isComposing,
  # then compositionend once the characters are chosen. Selenium can't drive a
  # real IME, so these are those same events, dispatched in the same order.
  test "pinyin still being converted is not searched, the converted word is" do
    compose("beij")
    sleep PAST_DEBOUNCE
    assert_not_requested :get, FORWARD_GEOCODE

    finish_composing("北京")

    assert_selector ".location-result", text: "Result for 北京"
    assert_requested :get, FORWARD_GEOCODE, query: hash_including("q" => "北京"), times: 1
    assert_not_requested :get, FORWARD_GEOCODE, query: hash_including("q" => "beij")
  end

  test "romaji still being converted is not searched, the converted word is" do
    compose("meguro")
    sleep PAST_DEBOUNCE
    assert_not_requested :get, FORWARD_GEOCODE

    finish_composing("目黒")

    assert_selector ".location-result", text: "Result for 目黒"
  end

  # Enter is how an input method confirms its characters. Taken as "pick the
  # highlighted result", it would move someone's start mid-word.
  test "enter while converting doesn't pick a result" do
    type_query("北京")
    assert_selector ".location-result", text: "Result for 北京"
    keydown("ArrowDown")
    assert_selector ".location-result.is-active"

    keydown("Enter", composing: true)

    sleep 0.3
    assert_selector ".location-result.is-active"
    assert_equal "Meguro", users(:walker).reload.current_location_name
  end

  test "typing back to a place already searched doesn't search it again" do
    type_query("目黒")
    assert_selector ".location-result", text: "Result for 目黒"

    type_query("目黒駅")
    assert_selector ".location-result", text: "Result for 目黒駅"

    type_query("目黒")
    assert_selector ".location-result", text: "Result for 目黒"
    sleep PAST_DEBOUNCE
    assert_requested :get, FORWARD_GEOCODE, query: hash_including("q" => "目黒"), times: 1
  end

  private

  # Types for real, then makes sure it arrived. Headless Chrome here sometimes
  # drops keystrokes the way it drops clicks (see click_and_confirm) - a first
  # run left the field empty after typing 渋谷 - so the fallback sets the value
  # through the DOM and fires the input event the controller listens for.
  def type_query(text)
    field = find("#location-query")
    field.set(text)
    return if field.value == text

    page.execute_script(<<~JS, field, text)
      const [field, text] = arguments
      field.value = text
      field.dispatchEvent(new InputEvent("input", { bubbles: true, data: text }))
    JS
  end

  def suggestion(query)
    {
      "geometry" => { "coordinates" => [139.70, 35.66] },
      "properties" => { "name" => "Result for #{query}", "place_formatted" => "Tokyo, Japan" }
    }
  end

  def compose(text)
    page.execute_script(<<~JS, find("#location-query"), text)
      const [field, text] = arguments
      field.focus()
      field.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
      field.value = text
      field.dispatchEvent(new InputEvent("input", { bubbles: true, isComposing: true, data: text }))
    JS
  end

  def finish_composing(text)
    page.execute_script(<<~JS, find("#location-query"), text)
      const [field, text] = arguments
      field.value = text
      field.dispatchEvent(new InputEvent("input", { bubbles: true, isComposing: true, data: text }))
      field.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: text }))
    JS
  end

  def keydown(key, composing: false)
    page.execute_script(<<~JS, find("#location-query"), key, composing)
      const [field, key, composing] = arguments
      field.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, isComposing: composing }))
    JS
  end
end
