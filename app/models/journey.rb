class Journey < ApplicationRecord
  has_many :walks
  has_many :saved_journeys, dependent: :destroy
  has_many :saving_users, through: :saved_journeys, source: :user

  # A journey is a "community route" if it has no theme (unthemed journeys are
  # community by default), or if a themed journey has had at least one walk
  # shared to the community (via Walk#share!).
  scope :community, -> { where(theme_key: [nil, ""]).or(where(id: Walk.shared.select(:journey_id))) }

  # Most recently shared-to-community walk first; journeys with no shared
  # walk yet (unthemed journeys can permanently lack one) fall back to
  # their own created_at so they don't sort arbitrarily.
  scope :newest_first, lambda {
    order(Arel.sql(<<~SQL.squish))
      COALESCE(
        (SELECT MAX(walks.shared_at) FROM walks WHERE walks.journey_id = journeys.id),
        journeys.created_at
      ) DESC
    SQL
  }

  def community_photos(limit: nil)
    scope = walks.recent_with_photo
    limit ? scope.limit(limit) : scope
  end

  # The newest shared photo, read off the walks association rather than
  # queried. community_photos applies a join/order/limit, which forces a fresh
  # query per journey and so silently defeats an eager load -- this is the form
  # to use anywhere a list of journeys has already preloaded its walks (see
  # CommunityRoutesController#index).
  def latest_community_photo
    walks.select { |walk| walk.shared? && walk.photo.attached? }
         .max_by { |walk| walk.completed_at || walk.shared_at }
         &.photo
  end

  # Both of these columns are nullable, and every card in the app renders them
  # -- so the nil handling lives here once rather than in each view.
  def duration_minutes
    estimated_duration_seconds && (estimated_duration_seconds / 60.0).round
  end

  def distance_km
    distance_meters && (distance_meters / 1000.0).round(1)
  end

  # Ranges are half-open so 1500 doesn't match two branches, and an unknown
  # distance returns nil rather than falling through to "Hard" -- a journey we
  # can't measure isn't the hardest one, it's simply unlabelled.
  def length_label
    return nil if distance_meters.nil?

    case distance_meters
    when 0...1500 then "Easy"
    when 1500...4000 then "Medium"
    else "Hard"
    end
  end

  # How many people have actually finished this walk.
  #
  # This used to be 40 + (id % 120) -- a number derived from the primary key
  # and rendered on the card as though people had been counted. Everything
  # here now comes from the walks table, so a route that nobody has walked
  # says so.
  #
  # Counted in Ruby rather than with .count for the same reason as
  # latest_community_photo above: CommunityRoutesController#index preloads
  # walks, and a COUNT would go back to the database once per card.
  def walker_count
    walks.select { |walk| walk.completed_at.present? }.map(&:user_id).uniq.size
  end

  # The average of the ratings people left, or nil when nobody has rated it.
  #
  # nil rather than 0.0: an unrated route has no rating, and "0.0" beside a
  # star reads as a bad one.
  def rating
    ratings = walks.filter_map(&:rating)
    return nil if ratings.empty?

    (ratings.sum / ratings.size.to_f).round(1)
  end

  def estimated_steps_display
    estimated_steps || "—"
  end

  def rating_display
    rating || "—"
  end

  def alternate
    others = Journey.where.not(id: id)
    others = others.where(estimated_duration_seconds: ..estimated_duration_seconds) if estimated_duration_seconds

    # .sample isn't a relation method -- it would load every matching journey
    # into memory just to discard all but one. Let the database pick.
    random = ->(scope) { scope.order(Arel.sql("RANDOM()")).first }
    random.call(others.where(theme_key: theme_key)) || random.call(others)
  end

  def saved_by?(user)
    saved_journeys.exists?(user_id: user.id)
  end

  # Neighborhood/district label for the card UI (e.g. "Meguro"). Set at
  # creation time by JourneyGenerator.
  #
  # This used to reverse-geocode lazily on read for journeys predating the
  # column, which meant a blocking Mapbox round trip plus an UPDATE per card
  # while rendering a list of them. Backfill instead:
  #   bin/rails journeys:backfill_location_names
  # Anything still missing falls back to the generic label rather than going
  # to the network mid-render.
  FALLBACK_LOCATION_NAME = "Nearby"

  def location_name
    super.presence || FALLBACK_LOCATION_NAME
  end

  # find routes within `radius_meters` of a point, closest first.
  #
  # The ORDER BY is bound through sanitize_sql_array rather than interpolated:
  # Arel.sql marks a string as trusted and switches off Rails' own injection
  # guard, so anything reaching it has to be sanitized here instead. Callers
  # currently pass float columns, but this is a public scope -- one caller
  # handing it params[:lat] shouldn't be all it takes.
  scope :near, lambda { |lat, lng, radius_meters = 3000|
    distance_order = sanitize_sql_array(
      ["start_point <-> ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography", lng.to_f, lat.to_f]
    )

    where("ST_DWithin(start_point, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)", lng, lat, radius_meters)
      .order(Arel.sql(distance_order))
  }

  PLACE_IMAGES = {
    "Meguro River Loop" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWl2njWwiwoNU7VP1wL1k6xUW7WE44yFymMmwBdR02vjpWgtTzESUyZIp3coC1r7jb_vCRu1k0XXCX88oKa1_uCUXyVLxSvvICfY90bgHz34aApjX2mFxqvKx2yb15O5kk1t2Xr7=s500",
    "Nakameguro Backstreets" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWktTtpRocPqCncbWpUzH8N3kJPFThuHR7QDz0T5rJfJIrm-aJZH527tUrcfdKShNROAgdRLlTdqAchqvbpOIUxHpiN0SGtqifao75cEDtZJqJRYWY8PLvw2NqsxkEUkkOzS_uxrRA=s500",
    "Yutenji Green Escape" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnE2AkzMKrI-5MgtOO2We2UIrEOzV_BwPHgdVYLRbe2zf7yDNGwi5w_2AhK107p6HffuR6_M_sP9NfdCZZvfbMIkHzbnKOsRn5YYXZtJH9jgmcMro4uCJ7X9M5pstxXWnSQRAmo=s500",
    "Riverside Stroll" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWkGNINhIGzMsuuEoV0gUJ6s8ecQAyTMbZaPCPFRN7ZIG_-yKM7reK4OoYQRwmz7IuHCa5NHRwUUAhKidWYLF3oT0X3ENAhqrlhyzji2WnvEwQhbgl75JTskGeaJIg0NPgKpHCxGkw=s2000",
    "Park Escape" => "https://images.unsplash.com/photo-1519331379826-f10be5486c6f?q=80&w=1740&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
    "Morning Refresh" => "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWmmP1UP1q-VF_q4qDur3KpBV4_ep0ioVA2xRh70f_YaZxjDGkOhs9OFKZjOX0riLHMAyAzMVdBX5DarOZ__43op4_2EVsxuvZv10JGVgdvONA_kKKXvFCigqWmLpFTMd5DsIrfX=s2000"
  }.freeze

  def placeholder_image
    PLACE_IMAGES[name] || PLACEHOLDER_IMAGES[id % PLACEHOLDER_IMAGES.size]
  end

  # Placeholder images
  PLACEHOLDER_IMAGES = [
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWmIbzDkbQKteSMpmw0K4p3aIYCqEYUxYeNqvziCIeUJMw1IbA5c_vK6BItlm_JAXaj8VHoOpLJhB79I3QiMMHimQVWAFVoICMWLjWkM75mLbaTE_zJIDQnDgBAFACgHFPRmRsod=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnEDlKMKnY_AIoNOwOwiNUO-j9TFVXlqD5kh9dowSCY2CDtPDCc7FDTWT9t7kMFZ6deIye0Wc5r7ROfhAQuHsbwFrzAxb8zzRkdNTyI23sD0TNIgqMEEeNxf_0b0UsZ1JsK_yXpsQ=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnhR37unymt0_QfrldIarhGRaf-fHsM-QGWabV6A_f2geaP0LtiPwCywQYl5CHIKT6xiaR-UOexzAiYfwI5w0bPhRT-vf8hboVWYKEwbVipPtbVCR6QuiG7zRJpUepweHii6tt7dg=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWnJxOsyKTWnG9cchTE4I1s5i3xwLddM10Y8M7Hy82_eX-Pahm4Ck3PzwLb7tBGk9iMn4jgvRj6F8OkFApyxZhvFxuU7_Uu9ZERFZUZhHk9t8u_KzyCDuD8Mn6KUDYdT0yKJK9peMA=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlSD5SFmc2LQPsdORxTNTKJ2ZBQGQNMR45qU_QxBJijKbvGM09DvtP2jAFQX-CCrZVDMK1X7V8cuvBavU2pv86r1efjOcB9npy_zJXcK7t5YiBygtizQcG5VeDxn-NYU53kBPQ=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlQ_zf5NQskgWi_WmraAlsyj9QFikhmgzlVUNpS11GaT-gNawBt1F5BBw3J42W-kemgym9MZHkF-R7bOoQgdqSzbusap5_sd6mZFgXAUhzCQqhgKmIw4Uzis_qkjJAbACfglVsC=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlrT_bbmnthSna1Wn41PYAvVSTk10ZEqd_jlLSvAQpsB98emmhyW4kZMD_mWk9Gdk1zO4HWVOV3JlcbwW_QfTVIkpYuYXhwXaMVS3e_XdNToMD2TNSI3Y1NaBzNZbsXsycXcuY7Ig=s2000",
    "https://lh3.googleusercontent.com/gps-cs-s/AHRPTWlOSFbSwUg0K8VDbGkylUKgKmaSxp7NACTqhMl_dmdFNGltBJTNUeT2Mnome-6303b3UVXfRctb402DI8DSGG4pClrwZREiazw1LIU2ZDNnJrNUiAmqy39CAn5eFaHXuTZNhyJy2Q=s2000"
  ]

  def carousel_images
    PLACEHOLDER_IMAGES.sample(3)
  end

  # decodes `encoded_polyline` (Google/Mapbox encoded polyline, precision 5) into
  # [lng, lat] pairs, ready to drop into a GeoJSON LineString for Mapbox GL.
  # Memoized: decoding walks the string character by character, and loop? alone
  # asks for it twice.
  def route_coordinates
    @route_coordinates ||= PolylineDecoder.decode(encoded_polyline)
  end

  def start_coordinates
    [start_point.x, start_point.y]
  end

  # Whether the route returns to (roughly) where it started, vs. ending somewhere else
  # (one-way). Compares the decoded route's first/last points rather than any stored flag,
  # since round_trip isn't persisted -- a small tolerance absorbs Mapbox's start/end snapping
  # to the nearest walkable path (a few meters), well under the length of any real one-way leg.
  def loop?
    coords = route_coordinates
    start_lng, start_lat = coords.first
    end_lng, end_lat = coords.last
    (start_lng - end_lng).abs < 0.0005 && (start_lat - end_lat).abs < 0.0005
  end

  def turn_waypoints(angle_threshold: 30)
    coords = route_coordinates # each pair is [lng, lat]
    return [] if coords.size < 3

    waypoints = [{ lat: coords[0][1], lng: coords[0][0], instruction: "start" }]

    coords.each_cons(3) do |a, b, c|
      delta = angle_delta(bearing(a, b), bearing(b, c))
      next if delta.abs < angle_threshold

      waypoints << { lat: b[1], lng: b[0], instruction: delta.positive? ? "right" : "left" }
    end

    waypoints << { lat: coords.last[1], lng: coords.last[0], instruction: "end" }
    waypoints
  end

  HIGHLIGHT_PHRASES = {
    "Nature" => { icon: "🌿", text: "Greenery along the way" },
    "Water" => { icon: "💧", text: "Passes near water" },
    "Quiet" => { icon: "🤫", text: "Calm, quiet stretches" },
    "Historic" => { icon: "🏛️", text: "Old streets and landmarks" },
    "Lively" => { icon: "🚶", text: "Passes active areas" },
    "Views" => { icon: "🌅", text: "Opens out to a view" },
    "Walk" => { icon: "☀️", text: "Mostly open streets" }
  }.freeze

  # Google place types (config/initializers/themes.rb) -> the phrases above.
  #
  # Needed because theme_tags renders the raw place-type slug ("Botanical
  # garden"), which never matched HIGHLIGHT_PHRASES' mood words -- so every
  # themed journey silently had zero highlights, and only the LLM-written
  # highlights_text ever showed. Left over from the Mapbox -> Google Places
  # migration, when the slugs changed and this mapping stopped lining up.
  CATEGORY_HIGHLIGHTS = {
    "park" => "Nature", "city_park" => "Nature", "national_park" => "Nature",
    "nature_preserve" => "Nature", "wildlife_refuge" => "Nature", "woods" => "Nature",
    "garden" => "Nature", "botanical_garden" => "Nature", "hiking_area" => "Nature",
    "campground" => "Nature", "picnic_ground" => "Nature",
    "lake" => "Water", "beach" => "Water", "marina" => "Water",
    "scenic_spot" => "Views", "observation_deck" => "Views", "mountain_peak" => "Views",
    "farmers_market" => "Lively", "flea_market" => "Lively", "market" => "Lively",
    "bakery" => "Lively", "cafe" => "Lively", "ice_cream_shop" => "Lively",
    "dessert_shop" => "Lively", "playground" => "Lively"
  }.freeze

  # For a themed journey, what the route passes comes from the theme's real
  # categories; anything the name/description mentions is folded in on top
  # (a generated description saying "quiet" earns the Quiet phrase). Unthemed
  # journeys have only their text to go on, as before.
  def highlights
    highlight_keys.filter_map { |key| HIGHLIGHT_PHRASES[key] }.first(3)
  end

  TEXT_TAG_KEYWORDS = {
    "Nature" => /tree|leaf|leaves|branch|garden|grass|greenery|forest|park/i,
    "Water" => /water|stream|river|lake|pond|shore|waterfront/i,
    "Quiet" => /quiet|hushed|still|calm|silence/i,
    "Historic" => /old|worn|weathered|stone|brick|landmark|monument/i,
    "Lively" => /market|bakery|bright|color|liveliness|delight/i
  }.freeze

  def tags
    return theme_tags if themed?

    text_derived_tags
  end

  private

  def highlight_keys
    (category_highlight_keys + text_tag_matches).uniq.presence || ["Walk"]
  end

  def category_highlight_keys
    return [] unless themed?

    THEMES.dig(theme_key.to_sym, :categories).to_a.filter_map { |slug| CATEGORY_HIGHLIGHTS[slug] }.uniq
  end

  def themed?
    theme_key.present? && THEMES.key?(theme_key.to_sym)
  end

  def theme_tags
    THEMES.dig(theme_key.to_sym, :categories).to_a.map { |slug| slug.tr("_", " ").capitalize }
  end

  def text_derived_tags
    text_tag_matches.presence || ["Walk"]
  end

  def text_tag_matches
    text = "#{name} #{description}"
    TEXT_TAG_KEYWORDS.select { |_, pattern| text.match?(pattern) }.keys
  end

  # `from`/`to` are [lng, lat] pairs, the shape route_coordinates yields.
  def bearing(from, to)
    GeoDistance.bearing(from[1], from[0], to[1], to[0])
  end

  def angle_delta(bearing_in, bearing_out)
    (((bearing_out - bearing_in) + 540) % 360) - 180 # normalized to -180..180
  end
end
