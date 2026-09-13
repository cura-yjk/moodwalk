require "test_helper"

class JourneyTest < ActiveSupport::TestCase
  test "fixtures load, including the PostGIS start point" do
    journey = journeys(:meguro_loop)
    assert_in_delta 35.68, journey.start_point.y, 0.0001
    assert_in_delta 139.77, journey.start_point.x, 0.0001
  end

  test "decodes its encoded polyline into [lng, lat] pairs" do
    coords = journeys(:meguro_loop).route_coordinates

    assert_equal 3, coords.size
    coords.each { |pair| assert_equal 2, pair.size }
    # Google's documented sample polyline starts at (38.5, -120.2).
    assert_in_delta(-120.2, coords.first[0], 0.0001)
    assert_in_delta 38.5, coords.first[1], 0.0001
  end

  test "memoizes the decoded coordinates rather than re-decoding" do
    journey = journeys(:meguro_loop)
    assert_same journey.route_coordinates, journey.route_coordinates
  end

  test "length_label bands a known distance and stays nil when distance is unknown" do
    assert_equal "Medium", journeys(:meguro_loop).length_label
    assert_nil journeys(:unmeasured).length_label,
               "an unmeasurable journey shouldn't be labelled the hardest"
  end

  test "length_label puts the band boundary in exactly one band" do
    journey = journeys(:meguro_loop)

    journey.distance_meters = 1500
    assert_equal "Medium", journey.length_label
    journey.distance_meters = 1499
    assert_equal "Easy", journey.length_label
    journey.distance_meters = 4000
    assert_equal "Hard", journey.length_label
  end

  test "duration and distance helpers tolerate missing values" do
    assert_equal 25, journeys(:meguro_loop).duration_minutes
    assert_in_delta 2.0, journeys(:meguro_loop).distance_km, 0.001

    assert_nil journeys(:unmeasured).duration_minutes
    assert_nil journeys(:unmeasured).distance_km
  end

  test "location_name falls back instead of reaching for the network" do
    # No webmock stub registered here on purpose: if this ever tries to
    # reverse-geocode on read again, WebMock raises and this test fails.
    assert_equal Journey::FALLBACK_LOCATION_NAME, journeys(:unmeasured).location_name
    assert_equal "Meguro", journeys(:meguro_loop).location_name
  end

  test "near finds journeys within the radius, closest first" do
    near = Journey.near(35.68, 139.77, 5000)

    assert_includes near, journeys(:meguro_loop)
    assert_equal journeys(:meguro_loop), near.first, "the closest journey should sort first"
  end

  test "near excludes journeys outside the radius" do
    assert_not_includes Journey.near(35.68, 139.77, 100), journeys(:unmeasured)
  end

  # The ORDER BY is built with Arel.sql, which disables Rails' injection guard,
  # so the coordinates have to be bound rather than interpolated.
  test "near does not interpolate raw input into its ORDER BY" do
    # Rejected as a bad float by the bound parameter rather than executed --
    # the previous version spliced this straight into the ORDER BY.
    assert_raises(ActiveRecord::StatementInvalid) do
      Journey.near(35.68, "139.77); DROP TABLE journeys; --", 1000).to_a
    end
  end

  test "saved_by? reflects whether the user bookmarked it" do
    journey = journeys(:meguro_loop)
    assert_not journey.saved_by?(users(:walker))

    journey.saved_journeys.create!(user: users(:walker))
    assert journey.reload.saved_by?(users(:walker))
  end
end
