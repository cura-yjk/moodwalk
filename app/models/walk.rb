class Walk < ApplicationRecord
  belongs_to :user
  belongs_to :journey
  has_one_attached :photo

  # Duration isn't stored directly in the DB — we derive it from the
  # timestamps we already have. Returns nil if the walk hasn't been
  # started/completed yet, so the view can handle that gracefully.
  def duration_in_minutes
    return nil unless started_at && completed_at

    ((completed_at - started_at) / 60).round
  end

  # Lifetime totals shown atop walks#index (km walked / hours outside /
  # walks). Scoped to completed walks, since only those carry a real
  # actual_distance/actual_steps/completed_at.
  def self.lifetime_stats(walks)
    completed = walks.select(&:completed_at)
    total_minutes = completed.sum { |walk| walk.duration_in_minutes || 0 }

    {
      distance_km: completed.sum { |walk| walk.actual_distance || 0 }.round,
      hours_outside: (total_minutes / 60.0).round,
      walks_count: completed.size
    }
  end
end
