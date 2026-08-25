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

  # Shared mood → emoji mapping. Centralizing this means the edit page's
  # mood picker and the index page's display always stay in sync — one
  # place to update if you add/change moods later.
  MOOD_EMOJIS = {
    "Sad" => "😢",
    "Down" => "🙁",
    "Okay" => "😐",
    "Good" => "🙂",
    "Great" => "😃",
    "Calmer" => "😌"
  }.freeze

  def mood_emoji(mood)
    # Fallback to a neutral emoji if a walk somehow has a mood value
    # not in the list, rather than raising an error or showing blank.
    MOOD_EMOJIS.fetch(mood, "🙂")
  end
end
