require "application_system_test_case"

# The path every user takes: pick a feeling, say how long you have, get a walk.
# Three Stimulus controllers, and a form that is not submitted by the button
# the user thinks submits it.
#
# Everything here asserts on `.is-open` rather than on the sheet's text. The
# sheet is hidden with `transform: translateY(100%)` and its backdrop with
# `opacity: 0`, both of which Capybara counts as visible -- so an assertion on
# the words inside it passes whether or not the sheet ever opened.
class GettingAWalkTest < ApplicationSystemTestCase
  setup { sign_in_as users(:walker) }

  test "a theme card opens the duration sheet, filled in for that theme" do
    pick_theme("calm")

    assert_selector ".bottom-sheet.is-open", wait: 3
    within(".bottom-sheet") do
      assert_text "Calm"
      assert_text "Quiet your mind"
    end
  end

  test "each theme card opens the sheet for its own theme" do
    THEMES.each do |key, theme|
      pick_theme(key)

      within(".bottom-sheet") { assert_text theme[:label], wait: 3 }
      close_sheet
    end
  end

  test "picking a theme and a duration produces a walk" do
    pick_theme("calm")
    choose_duration("20")

    assert_difference -> { Journey.count }, 1 do
      submit_sheet
    end

    assert_current_path %r{/journeys/\d+/walks/new}, wait: 5
  end

  test "the duration buttons record which one was chosen" do
    pick_theme("calm")
    choose_duration("30")

    assert_selector ".duration-option.selected", text: "30"
    assert_equal "30", find("input[name='duration_minutes']", visible: false).value
  end

  test "surprise me works like the named themes" do
    pick_theme("surprise_me")
    click_until(".no-rush-option", appears: ".no-rush-option.selected")

    assert_difference -> { Journey.count }, 1 do
      submit_sheet
    end
  end

  test "closing the sheet does not start a walk" do
    pick_theme("calm")

    assert_no_difference -> { Journey.count } do
      close_sheet
    end
  end

  # The Escape binding is exercised by dispatching the event rather than by
  # pressing the key: a real Escape sent through Selenium is not delivered in
  # this environment (the same input flake as click_and_confirm describes), so
  # this proves the handler is wired and reachable from window -- not that the
  # key itself works. That one needs a human in a real browser.
  test "escape is wired to close the sheet" do
    pick_theme("calm")

    page.execute_script("window.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))")

    assert_no_selector ".bottom-sheet.is-open", wait: 3
  end

  test "tapping the backdrop closes the sheet" do
    pick_theme("calm")

    # Clicked near the top, where the backdrop is actually exposed: its centre
    # sits behind the sheet, so a plain click lands on the sheet instead.
    page.execute_script("document.querySelector('.bottom-sheet-backdrop').click()")

    assert_no_selector ".bottom-sheet.is-open", wait: 3
  end

  test "the location bar opens the change panel" do
    assert_no_selector ".location-panel button", text: "Use my current location"

    wait_for_controller(".location-bar", "location-entry")
    click_until(".location-bar-change", appears: ".location-panel button.location-detect")

    assert_selector ".location-panel button", text: "Use my current location", wait: 3
  end

  test "See all reaches the community routes" do
    click_to("a.link-btn[href='#{community_routes_path}']", path: community_routes_path)
  end

  # Layout, not clicks. Selenium computes a native click's screen coordinates
  # from the real browser window, so once the viewport is narrowed -- by
  # resizing or by CDP device emulation, both tried -- clicks are delivered
  # outside the rendered page and no event reaches the document at all. The
  # buttons are fine; the harness cannot press them at this size. Interaction
  # is covered at desktop size above; what is worth checking here is the CSS,
  # which is the thing that actually breaks at 390px.
  test "the homepage fits a phone without sideways scrolling" do
    resize_to PHONE

    assert_no_horizontal_overflow
    assert_selector ".theme-card[data-theme='calm']", visible: true
    assert_selector ".location-bar", visible: true
  ensure
    resize_to DESKTOP
  end

  test "the theme cards stay on the screen at phone width" do
    resize_to PHONE

    offscreen = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".theme-card")).filter((card) => {
        const r = card.getBoundingClientRect();
        return r.left < 0 || r.right > window.innerWidth || r.width < 40;
      }).map((card) => card.dataset.theme)
    JS

    assert_equal [], offscreen, "theme cards fall outside a phone screen"
  ensure
    resize_to DESKTOP
  end

  private

  # The mood check-in also offers a button reading "Calm", so the theme cards
  # are addressed by the attribute the picker itself keys on.
  def pick_theme(key)
    wait_for_controller(".theme-picker", "duration-picker")
    click_until(".theme-card[data-theme='#{key}']", appears: ".bottom-sheet.is-open")
  end

  def assert_no_horizontal_overflow
    overflow = page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth")

    assert_operator overflow, :<=, 1, "the page scrolls sideways by #{overflow}px"
  end

  # Closes through the backdrop, which is what a user taps. Clicked through the
  # DOM because the backdrop's centre sits behind the sheet, so a positional
  # click lands on the sheet instead.
  def choose_duration(minutes)
    click_until(".duration-option[data-duration-picker-minutes-param='#{minutes}']",
                appears: ".duration-option.selected")
  end

  def submit_sheet
    attempt_click(".find-walk-btn")
    return if has_no_selector?(".bottom-sheet.is-open", wait: 10)

    attempt_click(".find-walk-btn", via_dom: true)
    assert_no_selector ".bottom-sheet.is-open", wait: 10
  end

  def close_sheet
    page.execute_script("document.querySelector('.bottom-sheet-backdrop').click()")
    assert_no_selector ".bottom-sheet.is-open", wait: 3
  end
end
