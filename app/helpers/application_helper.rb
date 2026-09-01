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

  # Short comparative word for the walk-history card's before → after mood
  # display (e.g. "Stressed → Calm" shows the "Calm" icon plus "Calmer"),
  # rather than spelling out both mood names as text.
  MOOD_CHANGE_LABELS = {
    "Stressed" => "More stressed",
    "Neutral" => "More neutral",
    "Calm" => "Calmer",
    "Good" => "Better"
  }.freeze

  def mood_change_label(mood_after)
    MOOD_CHANGE_LABELS.fetch(mood_after, mood_after)
  end

  def share_card_datetime(walk)
    timestamp = walk.completed_at || Time.current
    "#{timestamp.strftime('%-d %b').upcase} • #{timestamp.strftime('%-l:%M %p')}"
  end

  # walks#memory's "wanted to feel" fallback when there's no mood_before --
  # THEMES keys are always resolved to a real theme before a Journey is
  # saved (JourneysController#theme_key resolves "surprise_me" up front), so
  # no "surprise_me" special-casing is needed here.
  def theme_for(theme_key)
    return nil if theme_key.blank?

    THEMES[theme_key.to_sym]
  end
end
