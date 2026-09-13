# View-side shaping for walks#index. These were private methods on
# WalksController, but they're all presentation concerns -- how history is
# bucketed into sections, and what the exploration map needs to draw -- so
# they live with the view instead.
module WalksHelper
  # Walks bucketed into the headed sections walks#index renders, newest first.
  def group_walks_by_date(walks)
    walks.group_by { |walk| walk_section_label(walk.started_at.to_date) }
  end

  # A month name catches everything older, so no new branch is ever needed
  # here no matter how far back a walk happened.
  def walk_section_label(date)
    today = Date.current

    return "Today" if date == today
    return "Yesterday" if date == today - 1.day
    return "This week" if (today.beginning_of_week..today.end_of_week).cover?(date)
    return "Last week" if ((today.beginning_of_week - 1.week)...today.beginning_of_week).cover?(date)

    date.strftime("%B %Y") # e.g. "July 2026"
  end

  # Centers the exploration map on the user's current location when we have
  # one, falling back to the most recent walk's journey so the map still lands
  # somewhere sensible for users without a stored location.
  def exploration_map_center(walks)
    if current_user.current_longitude && current_user.current_latitude
      [current_user.current_longitude, current_user.current_latitude]
    else
      walks.first&.journey&.start_coordinates
    end
  end

  def exploration_photo_points(walks)
    walks.select { |walk| walk.photo.attached? }.map do |walk|
      lng, lat = walk.photo_coordinates
      { lng: lng, lat: lat, photo_url: url_for(walk.photo) }
    end
  end
end
