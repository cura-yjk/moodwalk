# Shared Faraday setup for the third-party APIs this app calls (Google Places
# via PoiFinder, Mapbox Directions via JourneyGenerator, Mapbox Geocoding via
# MapboxGeocoder and LocationsController).
#
# All of these run synchronously inside a request -- there's no background job
# for them yet -- and PoiFinder makes one call per theme category, serially, so
# a single slow upstream would otherwise pin a Puma thread indefinitely. The
# timeouts here are the backstop for that.
module ExternalApi
  OPEN_TIMEOUT_SECONDS = 5
  TIMEOUT_SECONDS = 10

  module_function

  def connection
    Faraday.new do |conn|
      conn.options.open_timeout = OPEN_TIMEOUT_SECONDS
      conn.options.timeout = TIMEOUT_SECONDS
    end
  end

  # Parses a JSON response body.
  #
  # Deliberately does *not* raise on a non-2xx status: both Google Places and
  # Mapbox report their own errors as structured JSON, and the callers read
  # those bodies (body["error"], body["code"]) to build a useful message. What
  # this does catch is the case those callers can't handle -- a gateway 5xx
  # returning an HTML error page, where a bare JSON.parse raises
  # JSON::ParserError and surfaces to the user as meaningless noise.
  def parse_json(response, service:)
    JSON.parse(response.body)
  rescue JSON::ParserError
    raise "#{service} returned an unreadable response (HTTP #{response.status})"
  end
end
