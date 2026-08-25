class Walk < ApplicationRecord
  belongs_to :user
  belongs_to :journey

  # Duration isn't stored directly in the DB — we derive it from the
  # timestamps we already have. Returns nil if the walk hasn't been
  # started/completed yet, so the view can handle that gracefully.
  def duration_in_minutes
    return nil unless started_at && completed_at

    ((completed_at - started_at) / 60).round
  end
end
