require "test_helper"

# Browser-level tests.
#
# The suite had 216 of them before this file existed and not one opened a
# browser -- while 19 Stimulus controllers and 1,772 lines of JavaScript sit
# between every button in this app and the server. A button that stopped doing
# anything would not have failed a single test.
#
# These cover the flows where a dead button costs the most: getting a walk,
# starting it, and the controls on a walk in progress.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  DESKTOP = [1280, 800].freeze
  PHONE = [390, 844].freeze

  # CI runners ship Chrome on the PATH; a developer machine often does not, but
  # Selenium Manager will have cached a Chrome for Testing build. Point at that
  # rather than requiring a system-wide install.
  cached = Dir[File.expand_path("~/.cache/selenium/chrome/*/*/chrome")].max
  Selenium::WebDriver::Chrome.path = cached if cached && !system("which google-chrome chromium >/dev/null 2>&1")

  # Geolocation is denied rather than left to the browser.
  #
  # The location bar asks for a fix on every page load and PATCHes /location
  # with whatever comes back, which then reverse-geocodes. On a CI runner that
  # resolves to the runner's own IP -- a first run reported coordinates in
  # Querétaro -- so the suite made an unstubbed request whose URL nobody could
  # predict, fired late enough to land after the stubs had been torn down. With
  # the permission denied the app takes its "we could not find you" path and
  # uses the location already on the user, which is what the fixtures set.
  driven_by :selenium, using: :headless_chrome, screen_size: DESKTOP do |options|
    options.add_argument("--deny-permission-prompts")
    options.add_argument("--use-fake-ui-for-media-stream")
  end

  setup { stub_outbound_apis }

  def sign_in_as(user, password: "password123")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_and_confirm("Log in", expect: /How would you like to feel/i)
  end

  # Clicks, then waits for proof the click landed, retrying once through the DOM.
  #
  # Headless Chrome here intermittently reports a successful click that the page
  # never receives: no exception from Selenium, and no pointerdown or click
  # event reaches the document, with the element connected, on screen, and
  # nothing overlapping it. Measured at roughly one click in ten. A JS-dispatched
  # click always lands, so the retry is a workaround for a flaky input channel
  # -- not a way of pressing a button that is genuinely unreachable, since the
  # first attempt is a real click and the DOM state is verified either way.
  def click_and_confirm(locator, expect:, wait: 5)
    press(locator)
    return if has_text?(expect, wait: wait)

    press(locator, via_dom: true)
    assert_text expect, wait: wait
  end

  # Re-finds by locator on every attempt: a handle held across a failed click
  # goes stale when the page settles underneath it, and a stale handle reads as
  # a broken feature rather than a lost click.
  def press(locator, via_dom: false)
    element = locator.is_a?(Capybara::Node::Element) ? locator : find_button_or_link(locator)
    page.execute_script("arguments[0].scrollIntoView({block: 'center'})", element)
    via_dom ? page.execute_script("arguments[0].click()", element) : element.click
  rescue Selenium::WebDriver::Error::StaleElementReferenceError,
         Selenium::WebDriver::Error::UnknownError
    retry unless locator.is_a?(Capybara::Node::Element)
    raise
  rescue Selenium::WebDriver::Error::ElementClickInterceptedError
    page.execute_script("arguments[0].click()", element)
  end

  # The same retry, for a click whose proof is an element rather than text.
  def click_until(selector, appears:, wait: 5)
    attempt_click(selector)
    return if has_selector?(appears, wait: wait)

    attempt_click(selector, via_dom: true)
    assert_selector appears, wait: wait
  end

  # ...and for a click whose proof is having gone somewhere.
  def click_to(selector, path:, wait: 5)
    attempt_click(selector)
    return if page.has_current_path?(path, wait: wait)

    attempt_click(selector, via_dom: true)
    assert_current_path path, wait: wait
  end

  # Re-finds the element each time: an element handle held across a failed
  # click can go stale when the page settles underneath it, and a stale handle
  # reads as a broken feature rather than a lost click.
  #
  # Scrolls first, because the sheet is taller than a CI runner's viewport and
  # its lower controls sit under the fixed navbar until they are scrolled to --
  # which Selenium reports as a click intercepted at a coordinate, not as
  # anything to do with the button.
  def attempt_click(selector, via_dom: false)
    element = find(selector, wait: 5)
    page.execute_script("arguments[0].scrollIntoView({block: 'center'})", element)
    via_dom ? page.execute_script("arguments[0].click()", element) : element.click
  rescue Selenium::WebDriver::Error::StaleElementReferenceError,
         Selenium::WebDriver::Error::UnknownError
    # "Node with given id does not belong to the document" arrives as
    # UnknownError and means the same thing: the page moved on, look again.
    retry
  rescue Selenium::WebDriver::Error::ElementClickInterceptedError
    # Something is over it right now. The caller checks whether the click
    # landed and will come back through here for the DOM attempt.
    page.execute_script("arguments[0].click()", find(selector, wait: 5))
  end

  def find_button_or_link(locator)
    find(:button, locator, wait: 5)
  rescue Capybara::ElementNotFound
    find(:link_or_button, locator, wait: 5)
  end

  # Waits for a Stimulus controller to be connected to an element.
  #
  # Stimulus connects after the page has loaded, and a click delivered before
  # it does is simply lost -- which presents as a button that "sometimes" does
  # nothing, and as a flaky test rather than a broken feature. Waiting for the
  # controller instance is deterministic; retrying the click is not.
  def wait_for_controller(selector, identifier)
    connected = "!!(window.Stimulus && window.Stimulus.getControllerForElementAndIdentifier(" \
                "document.querySelector('#{selector}'), '#{identifier}'))"

    Timeout.timeout(10) { sleep 0.05 until page.evaluate_script(connected) }
  rescue Timeout::Error
    flunk "the #{identifier} controller never connected to #{selector}"
  end

  # Resizes the live browser rather than calling driven_by again in a subclass:
  # a second driven_by re-registers the same driver for the whole run, so a
  # phone-sized class silently shrinks every other class's window too.
  def resize_to(dimensions)
    page.driver.browser.manage.window.resize_to(*dimensions)
  end

  # Nothing here may reach the real Google or Mapbox. The server runs in this
  # process during a system test, so WebMock applies exactly as it does
  # elsewhere.
  def stub_outbound_apis
    stub_request(:post, PoiFinder::NEARBY_SEARCH_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "places" => nearby_places }.to_json)

    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/directions/v5/mapbox/walking/})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "code" => "Ok",
        "routes" => [{ "distance" => 1_600.0, "duration" => 1_200.0,
                       "geometry" => "_p~iF~ps|U_ulLnnqC", "legs" => [{ "steps" => [] }] }]
      }.to_json)

    stub_request(:get, %r{\Ahttps://api\.mapbox\.com/search/geocode/v6/reverse})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "features" => [{ "properties" => { "name" => "Meguro" } }] }.to_json)

    # The map tiles and fonts a real page would fetch. Blocked rather than
    # served: the tests assert on the app's own chrome, not on Mapbox's canvas.
    stub_request(:any, %r{\Ahttps://api\.mapbox\.com/(styles|fonts|v4)}).to_return(status: 200, body: "")
  end

  def nearby_places
    6.times.map do |i|
      point = GeoDistance.destination_point(35.68, 139.77, 300 + (i * 200), (i * 61) % 360)
      { "id" => "poi-#{i}", "displayName" => { "text" => "Place #{i}" },
        "location" => { "latitude" => point[:lat], "longitude" => point[:lng] } }
    end
  end
end
