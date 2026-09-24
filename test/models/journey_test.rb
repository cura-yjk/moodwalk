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

  # Regression: theme_tags renders Google place-type slugs ("Botanical
  # garden") while HIGHLIGHT_PHRASES is keyed on mood words, so themed
  # journeys resolved to zero highlights and the route preview rendered an
  # empty list whenever the LLM-written highlights_text wasn't there.
  test "a themed journey has highlights without needing the LLM" do
    journey = journeys(:meguro_loop) # theme_key: calm
    assert_nil journey.highlights_text

    highlights = journey.highlights
    assert_not_empty highlights, "themed journeys must resolve highlights from their categories"
    assert(highlights.all? { |h| h[:icon].present? && h[:text].present? })
  end

  test "every theme resolves to at least one highlight" do
    THEMES.each_key do |theme_key|
      journey = Journey.new(theme_key: theme_key.to_s, name: "x", encoded_polyline: "x")
      assert_not_empty journey.highlights, "#{theme_key} resolved to no highlights"
    end
  end

  test "highlights fold in what the description mentions, on top of the categories" do
    journey = journeys(:meguro_loop)
    journey.description = "Old stone walls and a quiet lane."

    texts = journey.highlights.map { |h| h[:text] }
    assert_includes texts, JourneyHighlights::HIGHLIGHT_PHRASES["Quiet"][:text]
  end

  test "an unthemed journey still derives highlights from its text" do
    journey = journeys(:unmeasured)
    journey.description = "A path by the river, under the trees."

    texts = journey.highlights.map { |h| h[:text] }
    assert_includes texts, JourneyHighlights::HIGHLIGHT_PHRASES["Water"][:text]
    assert_includes texts, JourneyHighlights::HIGHLIGHT_PHRASES["Nature"][:text]
  end

  test "highlights are capped at three" do
    assert_operator journeys(:meguro_loop).highlights.size, :<=, 3
  end

  # The cards show invented numbers again for now -- see PlaceholderStats --
  # because only one walk in the database carries a rating. The real figures
  # below still exist, are still tested, and are two view lines away.
  test "the placeholder stats a card shows are stable for a given route" do
    journey = journeys(:meguro_loop)

    assert_equal journey.placeholder_walker_count, journey.placeholder_walker_count
    assert_equal journey.placeholder_rating, journey.placeholder_rating
  end

  test "the placeholder rating looks like a rating" do
    Journey.find_each do |journey|
      assert_includes 1.0..5.0, journey.placeholder_rating
    end
  end

  # These are what the cards will show once there is enough real data. Kept
  # working and tested while the placeholders are on screen, so switching over
  # is a view change and nothing else.

  test "counts the people who actually finished the walk" do
    journey = journeys(:meguro_loop)

    # Fixtures: walker completed one and has another still in progress; other
    # completed one. Two people have finished it, not three walks.
    assert_equal 2, journey.walker_count
  end

  test "someone walking the same route twice is still one person" do
    journey = journeys(:meguro_loop)
    journey.walks.create!(user: users(:walker), started_at: 2.hours.ago, completed_at: 1.hour.ago)

    assert_equal 2, journey.reload.walker_count, "a repeat walk was counted as another walker"
  end

  test "a walk nobody has finished has no walkers, rather than a flattering number" do
    assert_equal 0, journeys(:unmeasured).walker_count
  end

  test "averages the ratings people left" do
    journey = journeys(:meguro_loop)
    walks(:completed_walk).update!(rating: 5)
    walks(:other_users_walk).update!(rating: 4)

    assert_in_delta 4.5, journey.reload.rating, 0.001
  end

  test "an unrated walk has no rating rather than a zero" do
    # 0.0 beside a star reads as a bad rating; no rating is not a bad rating.
    assert_nil journeys(:meguro_loop).rating
    assert_equal "—", journeys(:meguro_loop).rating_display
  end

  test "an in-progress walk is not counted as a finished one" do
    journey = journeys(:unmeasured)
    journey.walks.create!(user: users(:walker), started_at: 1.hour.ago)

    assert_equal 0, journey.reload.walker_count
  end

  # CommunityRoutesController#index preloads walks and renders one card per
  # journey; a COUNT or an AVG per card would go back to the database each time.
  test "reads both off the preloaded walks rather than querying per card" do
    journeys = Journey.where(id: journeys(:meguro_loop).id).includes(:walks).to_a

    assert_no_queries do
      journeys.each do |journey|
        journey.walker_count
        journey.rating
      end
    end
  end

  test "saved_by? reflects whether the user bookmarked it" do
    journey = journeys(:meguro_loop)
    assert_not journey.saved_by?(users(:walker))

    journey.saved_journeys.create!(user: users(:walker))
    assert journey.reload.saved_by?(users(:walker))
  end

  # ShortlistRouter asks a route for its overlap to accept it, to rank it and
  # again to report it. Measured more than once per route, a long route's
  # build went from ~50ms to ~750ms, and a browser test's walk timed out.
  test "measures how much of the route re-walks itself once, however often asked" do
    journey = Journey.new(encoded_polyline: journeys(:meguro_loop).encoded_polyline)
    measured = 0
    original = RouteOverlap.method(:ratio)
    RouteOverlap.define_singleton_method(:ratio) do |coordinates|
      measured += 1
      original.call(coordinates)
    end

    3.times { journey.overlap_ratio }

    assert_equal 1, measured
  ensure
    RouteOverlap.define_singleton_method(:ratio, original)
  end


  # --- alternate ----------------------------------------------------------
  #
  # "Choose alternate journey" offers a saved walk instead of this one. It used
  # to pick from the whole database, so the alternate could start 1.65km off
  # (measured) or in another city - a walk the user couldn't start from where
  # they are. It has to start near where this one does.

  test "an alternate starts near where this walk starts" do
    nearby = saved_walk(theme_key: "calm", lng: 139.7705, lat: 35.6805) # ~70m away
    saved_walk(theme_key: "calm", lng: 139.86, lat: 35.63)             # ~9km away

    assert_equal nearby, journeys(:meguro_loop).alternate
  end

  test "no alternate when every other walk starts far away" do
    journeys(:near_suggestion).destroy!
    saved_walk(theme_key: "calm", lng: 139.86, lat: 35.63)

    assert_nil journeys(:meguro_loop).alternate
  end

  test "another theme will do, but still only nearby" do
    saved_walk(theme_key: "calm", lng: 139.86, lat: 35.63)

    assert_equal journeys(:near_suggestion), journeys(:meguro_loop).alternate # unthemed, ~140m away
  end

  # meguro_loop is 25 minutes (1500s); RouteBuilder's 25% tolerance makes that
  # 1125-1875s. The alternate used to be any walk no longer, down to a
  # 7-minute one offered in place of a 21-minute walk (measured).
  test "not a walk much shorter than this one" do
    journeys(:near_suggestion).destroy!
    saved_walk(theme_key: "calm", lng: 139.7705, lat: 35.6805, seconds: 1100)

    assert_nil journeys(:meguro_loop).alternate
  end

  test "a walk a little longer will do" do
    longer = saved_walk(theme_key: "calm", lng: 139.7705, lat: 35.6805, seconds: 1850)

    assert_equal longer, journeys(:meguro_loop).alternate
  end

  test "not a walk much longer either" do
    journeys(:near_suggestion).destroy!
    saved_walk(theme_key: "calm", lng: 139.7705, lat: 35.6805, seconds: 1900)

    assert_nil journeys(:meguro_loop).alternate
  end

  test "picks at random among the nearby walks, not always the closest" do
    closest = saved_walk(theme_key: "calm", lng: 139.7702, lat: 35.6802)
    further = saved_walk(theme_key: "calm", lng: 139.7720, lat: 35.6815)

    # uncached: the query cache would answer the same RANDOM() query with its
    # first result every time. Each tap in the app is its own request.
    picks = Journey.uncached { Array.new(30) { journeys(:meguro_loop).alternate }.uniq }

    assert_equal [closest, further].map(&:id).sort, picks.map(&:id).sort
  end


  private

  # 1200s by default: within 25% of meguro_loop's 1500s, so only where it
  # starts is being tested unless a test says otherwise.
  def saved_walk(theme_key:, lng:, lat:, seconds: 1200)
    Journey.create!(name: "Walk", theme_key: theme_key, encoded_polyline: journeys(:meguro_loop).encoded_polyline,
                    start_point: "SRID=4326;POINT(#{lng} #{lat})", estimated_duration_seconds: seconds)
  end

end
