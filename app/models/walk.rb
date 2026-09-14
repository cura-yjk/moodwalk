class Walk < ApplicationRecord
  # Average meters per step -- converts a walked distance into a rough step
  # count. The single source of truth for this: JourneyGenerator uses it for a
  # journey's *planned* steps and finalize_actual_path! for the *actual* ones,
  # so the two must divide by the same number or every walk reports a step
  # delta it didn't really have. Mirrored (deliberately) as STEP_LENGTH_METERS
  # in walking_controller.js, which counts steps live during the walk.
  STEP_LENGTH_METERS = 0.76

  # The moods a walk can be tagged with, before and after. Lives here rather
  # than in ApplicationHelper so the model can validate against it and the
  # controller doesn't have to reach into a view helper's constant -- the
  # helper's icon map keys off this list (see ApplicationHelper::MOOD_ICONS).
  MOODS = %w[Stressed Neutral Calm Good Energised].freeze

  belongs_to :user
  belongs_to :journey
  has_one_attached :photo

  # Raw GPS breadcrumbs streamed in during the walk (see WalksController#track).
  # finalize_actual_path! collapses them into actual_path once the walk ends.
  has_many :walk_track_points, dependent: :destroy

  validates :rating, inclusion: { in: 1..5 }, allow_nil: true

  # Both moods arrive from hidden fields set by JS rather than from a form the
  # user fills in, so they're validated rather than trusted. Without this an
  # arbitrary mood_after persists and then raises in the views that render its
  # icon, locking the user out of their own walk list.
  validates :mood_before, :mood_after, inclusion: { in: MOODS }, allow_nil: true

  scope :completed, -> { where.not(completed_at: nil) }
  scope :shared, -> { where.not(shared_at: nil) }
  scope :with_photo, -> { joins(:photo_attachment) }
  scope :recent_with_photo, -> { shared.with_photo.order(completed_at: :desc) }

  def share!(attrs = {})
    update!(attrs.merge(shared_at: Time.current))
  end

  def shared?
    shared_at.present?
  end

  # GPS fix captured client-side at the moment the photo was taken (see
  # walking_controller.js#photoTaken). Falls back to the journey's start
  # point for walks/photos predating that capture, or if the browser
  # couldn't get a location fix in time.
  def photo_coordinates
    return [photo_longitude, photo_latitude] if photo_longitude && photo_latitude

    journey.start_coordinates
  end

  # [lng, lat] pairs for the path the user actually walked, ready to drop into
  # a GeoJSON LineString (same shape/order as Journey#route_coordinates). Empty
  # until finalize_actual_path! has run, or if the walk was never tracked.
  def actual_route_coordinates
    return [] unless actual_path

    actual_path.points.map { |point| [point.x, point.y] }
  end

  # Called when the walk ends (WalksController#complete). Collapses the raw GPS
  # breadcrumbs into a single geography(LineString) on actual_path and fills in
  # the real distance/step totals.
  #
  # The server-derived totals win when we have a real tracked line -- they're
  # measured off the recorded path rather than accumulated client-side. With
  # fewer than 2 usable points (location denied, desktop browser, very short
  # walk) there's nothing to measure, so it falls back to whatever the client
  # counted, and finally to the journey's own estimates, so the completion
  # screen always has numbers to show.
  def finalize_actual_path!(fallback_distance_km: nil, fallback_steps: nil)
    line = tracked_line_string
    meters = line&.length # spherical factory reports length in meters

    update!(
      completed_at: Time.current,
      actual_path: line,
      actual_distance: meters ? (meters / 1000.0).round(2) : (fallback_distance_km || estimated_distance_km),
      actual_steps: meters ? (meters / STEP_LENGTH_METERS).round : (fallback_steps || journey.estimated_steps)
    )
  end

  # Duration isn't stored directly in the DB — we derive it from the
  # timestamps we already have. Returns nil if the walk hasn't been
  # started/completed yet, so the view can handle that gracefully.
  def duration_in_minutes
    return nil unless started_at && completed_at

    ((completed_at - started_at) / 60).round
  end

  # geography(LineString) through the recorded breadcrumbs in walk order, or nil
  # if there aren't at least two to connect. Built with the same spherical
  # factory JourneyGenerator uses to write start_point.
  def tracked_line_string
    coordinates = walk_track_points.order(:recorded_at).pluck(:longitude, :latitude)
    return if coordinates.size < 2

    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    factory.line_string(coordinates.map { |lng, lat| factory.point(lng, lat) })
  end

  def estimated_distance_km
    journey.distance_meters && (journey.distance_meters / 1000.0).round(2)
  end

  # Lifetime totals shown atop walks#index (km walked / hours outside /
  # walks). Scoped to completed walks, since only those carry a real
  # actual_distance/actual_steps/completed_at.
  #
  # Aggregated in SQL: this used to load every walk the user had ever taken
  # into memory and sum in Ruby, which grows without bound as they walk more.
  def self.lifetime_stats(walks)
    completed = walks.completed
    seconds_outside = completed.sum("EXTRACT(EPOCH FROM (completed_at - started_at))").to_f

    {
      distance_km: completed.sum(:actual_distance).to_f.round,
      hours_outside: (seconds_outside / 3600.0).round,
      walks_count: completed.count
    }
  end
end
