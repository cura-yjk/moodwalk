require "test_helper"

# The suite must never run on a real credential.
#
# test_helper pins the API-key variables before the app boots, but it has to
# name each one -- and dotenv-rails loads .env in the test environment, so any
# variable it misses arrives holding whatever the developer's real key is.
#
# Both halves of that have already happened here. LlmChat#keys reads
# GEMINI_API_KEYS first while only the singular was pinned, so the suite ran on
# the production Gemini keys until a failure printed one into the output; and
# the Mapbox token, which every map view renders into the page, was never
# pinned at all.
#
# This guards the ambient environment rather than any one service, so a
# variable added to .env without a matching pin fails here instead of on
# someone's bill -- or in a screenshot.
#
# Every assertion is a bare `assert` with a hand-written message, never
# assert_equal: a failing assert_equal prints the values it compared, which for
# this test is the live credential, into CI logs -- on the one run that proves
# the credential is exposed.
class CredentialsPinnedTest < ActiveSupport::TestCase
  # Each variable the app reads, and the pinned value it must hold.
  PINNED = {
    "GEMINI_API_KEYS" => "test-gemini-key-not-a-real-credential",
    "GEMINI_API_KEY" => "test-gemini-key-not-a-real-credential",
    "ANTHROPIC_API_KEY" => "test-anthropic-key-not-a-real-credential",
    "OPENAI_API_KEY" => "test-openai-key-not-a-real-credential",
    "MAPBOX_ACCESS_TOKEN" => "test-mapbox-token-not-a-real-credential",
    "GOOGLE_PLACES_API_KEY" => "test-google-places-key-not-a-real-credential"
  }.freeze

  test "no credential the app reads carries a real value during the test run" do
    PINNED.each do |name, expected|
      values = ENV.fetch(name, "").split(",").map(&:strip).reject(&:empty?)

      assert values.any?, "#{name} is not pinned, so .env decides what the suite runs on"
      assert values.all?(expected), "#{name} is holding a real credential during the test run"
    end
  end

  test "the keys LlmChat would spend are all pinned test values" do
    keys = LlmChat.keys

    assert keys.any?, "LlmChat has no key configured, so the suite proves nothing about what it would spend"
    assert keys.all?(PINNED.fetch("GEMINI_API_KEYS")), "LlmChat would spend a key that is not the pinned test value"
  end

  # The map views render this straight into the HTML, so an unpinned token ends
  # up in the body of every controller test that renders one.
  test "no rendered page can carry a real map token" do
    assert ENV.fetch("MAPBOX_ACCESS_TOKEN", nil) == PINNED.fetch("MAPBOX_ACCESS_TOKEN"),
           "MAPBOX_ACCESS_TOKEN is not the pinned value, so rendered pages carry a real token"
  end
end
