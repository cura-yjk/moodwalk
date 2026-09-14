class WalkTrackPoint < ApplicationRecord
  belongs_to :walk

  # Cap on how many breadcrumbs one #track request may insert. The client
  # batches a handful at a time (see walking_controller.js#flushBreadcrumbs);
  # this just stops a single request from inserting an unbounded number of rows.
  MAX_POINTS_PER_BATCH = 500

  # Normalizes a batch of raw GPS fixes from the browser into rows for
  # insert_all, which needs uniform keys and won't set timestamps itself.
  # Points missing a coordinate are dropped rather than inserted as NULLs.
  def self.rows_for(walk, points, now: Time.current)
    Array(points).first(MAX_POINTS_PER_BATCH).filter_map do |point|
      next if point[:latitude].blank? || point[:longitude].blank?

      row_for(walk, point, now)
    end
  end

  def self.row_for(walk, point, now)
    {
      walk_id: walk.id,
      latitude: point[:latitude],
      longitude: point[:longitude],
      accuracy_meters: point[:accuracy_meters].presence,
      recorded_at: point[:recorded_at].presence || now,
      created_at: now,
      updated_at: now
    }
  end
  private_class_method :row_for
end
