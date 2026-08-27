module ApplicationHelper
  def active_icon_class(path)
    "highlight-icon" if current_page?(path)
  end

  def time_based_greeting
    current_time = Time.current.hour
    message = ""
    if current_time.between?(0, 12)
      message = "Good Morning"
    elsif current_time.between?(12, 18)
      message = "Good Afternoon"
    else
      message = "Good Evening"
    end
    message
    # current_time
  end

  # Shared mood → icon mapping. Centralizing this means the edit page's
  # mood picker and the index page's display always stay in sync — one
  # place to update if you add/change moods later.
  MOOD_ICONS = {
    "Stressed" => "moods/mood-stressed.png",
    "Neutral" => "moods/mood-neutral.png",
    "Calm" => "moods/mood-calm.png",
    "Good" => "moods/mood-good.png",
    "Energised" => "moods/mood-energised.png"
  }.freeze

  def mood_icon(mood)
    MOOD_ICONS.fetch(mood)
  end
end
