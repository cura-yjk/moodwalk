require "test_helper"

# Every third-party call in the app is built here, so the timeouts below are
# the only thing standing between one slow upstream and a pinned Puma thread:
# these calls run synchronously inside the request, and PoiFinder makes one per
# theme category.
class ExternalApiTest < ActiveSupport::TestCase
  test "every connection carries both timeouts" do
    connection = ExternalApi.connection

    assert_equal ExternalApi::OPEN_TIMEOUT_SECONDS, connection.options.open_timeout
    assert_equal ExternalApi::TIMEOUT_SECONDS, connection.options.timeout
  end

  test "the timeouts are bounded, not merely set" do
    # A connection that waits a minute is as good as one that waits forever,
    # for a request a person is sitting in front of.
    assert_operator ExternalApi::OPEN_TIMEOUT_SECONDS, :<=, 10
    assert_operator ExternalApi::TIMEOUT_SECONDS, :<=, 15
  end

  test "callers each get their own connection rather than sharing one" do
    # PoiFinder fetches its categories on separate threads; a shared Faraday
    # connection would be shared mutable state across them.
    assert_not_same ExternalApi.connection, ExternalApi.connection
  end

  test "parses a JSON body" do
    response = fake_response(status: 200, body: { "places" => [] }.to_json)

    assert_equal({ "places" => [] }, ExternalApi.parse_json(response, service: "Google Places"))
  end

  # Both upstreams report their own errors as structured JSON, and the callers
  # read those bodies to build a useful message -- so a non-2xx with a readable
  # body must come back parsed, not raised.
  test "an error body is handed back for the caller to read, not raised" do
    response = fake_response(status: 429, body: { "error" => { "message" => "quota" } }.to_json)

    parsed = ExternalApi.parse_json(response, service: "Google Places")

    assert_equal "quota", parsed.dig("error", "message")
  end

  # What the callers cannot handle: a gateway returning an HTML error page,
  # where a bare JSON.parse raises JSON::ParserError and reaches the user as
  # meaningless noise.
  test "an unreadable body becomes an error naming the service and status" do
    response = fake_response(status: 502, body: "<html><body>Bad Gateway</body></html>")

    error = assert_raises(RuntimeError) { ExternalApi.parse_json(response, service: "Mapbox Directions") }

    assert_match "Mapbox Directions", error.message
    assert_match "502", error.message
  end

  test "an empty body is unreadable rather than silently nil" do
    error = assert_raises(RuntimeError) { ExternalApi.parse_json(fake_response(status: 200, body: ""), service: "X") }

    assert_match "unreadable", error.message
  end

  private

  def fake_response(status:, body:)
    Struct.new(:status, :body).new(status, body)
  end
end
