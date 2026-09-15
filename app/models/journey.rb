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

  def placeholder_image
    JourneyImages.for(name: name, id: id)
  end

  def carousel_images
    JourneyImages.carousel
  end

  # The route's shape: its decoded coordinates, whether it comes back to where
  # it started, and where it turns. Owned by RouteGeometry, which needs nothing
  # from the record but the polyline and the start point.
  delegate :route_coordinates, :loop?, :turn_waypoints, to: :geometry

  def start_coordinates
    [start_point.x, start_point.y]
  end

  # What the route passes, as a few short phrases for the preview, and the
  # words shown as tags. Both are derived from the theme and the text -- see
  # JourneyHighlights, which owns the tables behind them.
  def highlights
    JourneyHighlights.new(theme_key: theme_key, text: "#{name} #{description}").phrases
  end

  def tags
    JourneyHighlights.new(theme_key: theme_key, text: "#{name} #{description}").tags
  end

  private

  # Memoized: the geometry decodes the polyline once and every caller shares it.
  def geometry
    @geometry ||= RouteGeometry.new(encoded_polyline: encoded_polyline)
  end
end
