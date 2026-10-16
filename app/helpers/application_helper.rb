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
  # place to update if you add/change moods later. Keyed off Walk::MOODS,
  # which is also what the model validates against.
  MOOD_ICONS = Walk::MOODS.index_with { |mood| "moods/mood-#{mood.downcase}.png" }.freeze

  # Falls back to the neutral icon rather than raising: Walk validates its
  # moods, but historical rows predate that validation, and a missing icon
  # shouldn't take down a whole walk list.
  DEFAULT_MOOD_ICON = MOOD_ICONS.fetch("Neutral")

  def mood_icon(mood)
    MOOD_ICONS.fetch(mood, DEFAULT_MOOD_ICON)
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

  # A journey's card picture: the newest photo a walker shared of it, or else
  # one of the app's bundled photos.
  def journey_card_image(journey, **)
    image_tag(journey.latest_community_photo || bundled_card_photo(journey), **)
  end

  # Free photos under the Unsplash License, bundled with the app so nothing on
  # a card loads from a third party or can break. They replaced hand-copied
  # Google photo URLs, two of which had started returning 403. Picked by id,
  # so a journey always shows the same one.
  #   walk-1  Tsuyoshi Kozu                  unsplash.com/photos/Q6sCJFHCubc
  #   walk-2  PJH                            unsplash.com/photos/uMXctRQHuqk
  #   walk-3  Mariola Grobelska              unsplash.com/photos/PDBwoGtYT1A
  #   walk-4  Jezael Melgoza                 unsplash.com/photos/htW2yNbSx-U
  #   walk-5  PJH                            unsplash.com/photos/I2e5b8ppox4
  #   walk-6  Willian Justen de Vasconcellos unsplash.com/photos/ydJpFcxaVH0
  #   river   Simon Ma (the Meguro River)    unsplash.com/photos/9vfxYMmEsKo
  #   temple  Johnny Ho (a temple in Meguro) unsplash.com/photos/-ViO1WRq7Hk
  BUNDLED_CARD_PHOTOS = (1..6).map { |n| "cards/walk-#{n}.jpg" }.freeze

  # A route named for a river shows the river, and one named for Yutenji a
  # temple path, rather than a street in Kyoto.
  NAMED_CARD_PHOTOS = {
    /river/i => "cards/river.jpg",
    /yutenji|temple/i => "cards/temple.jpg"
  }.freeze

  def bundled_card_photo(journey)
    NAMED_CARD_PHOTOS.find { |pattern, _| journey.name.to_s.match?(pattern) }&.last ||
      BUNDLED_CARD_PHOTOS[journey.id.to_i % BUNDLED_CARD_PHOTOS.size]
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
