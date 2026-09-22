require "ruby_llm/schema" # gem 'ruby_llm-schema'

# Writes the atmospheric description for a route whose waypoints have already
# been chosen (by PoiSelector). This used to also pick the waypoints, but that
# was really a geometry problem wearing an LLM costume - see PoiSelector for
# why that moved to plain Ruby. Description writing is the part that's
# genuinely LLM-shaped: the tone rules below are hard to encode as templates.
class RouteDescriber
  Result = Struct.new(:success?, :description, :error, keyword_init: true)

  class DescriptionSchema < RubyLLM::Schema
    string :description,
           description: "1-2 sentence atmospheric route description, grounded only in the " \
                        "selected places but naming none of them by name"
  end

  SYSTEM_PROMPT = <<~PROMPT
    You write short descriptions for walking routes in a mood-support app.
    The people using this app are often physically, emotionally, or mentally
    overwhelmed. Your writing should never add to that.

    Rules:
    - Write 1-2 short sentences. No more.
    - Use plain, concrete, sensory language (what they'll see, hear, feel
      underfoot) - not abstract mood language.
    - Never use exclamation points. Never sound falsely cheerful or upbeat.
    - Never use pressure, achievement, or challenge framing ("push yourself",
      "you've got this", "make the most of it", "don't miss out").
    - Never reference the user's emotional or mental state directly - no
      "you deserve this," "you need this," or similar. Describe the place,
      not the person.
    - Never use guilt, urgency, or scarcity language.
    - Ground every description only in the real places provided below - do
      not invent details about places that weren't given to you.
    - Do not name specific places, streets, or venues in the description -
      describe what's there (the water, the trees, the quiet), not what
      it's called. Naming a place turns "just walk" into "go find this,"
      which is one more thing to figure out.

    Given a theme and the real places already chosen for this walk, in
    walking order, write a short description of the route grounded in what's
    actually there.
  PROMPT

  # Plain-Ruby stand-in for when the LLM is unavailable (no credits, rate
  # limited, timed out). A route's description is prose for a card -- losing
  # it should cost the description, not the whole walk -- so RouteBuilder
  # falls back to this rather than failing. It lives here, next to
  # SYSTEM_PROMPT, because it has to obey the same tone rules: concrete and
  # sensory, no cheerfulness, no pressure, nothing about how the reader
  # feels, and -- like the prompt says -- no place names.
  #
  # Keyed on the Google place types in config/initializers/themes.rb; the
  # values describe what's there, not what it's called.
  # Each value is a single phrase with no internal "and", so they can be
  # joined into a list without the sentence stacking conjunctions.
  FEATURE_NOUNS = {
    "park" => "trees", "city_park" => "trees", "national_park" => "trees",
    "nature_preserve" => "trees", "wildlife_refuge" => "trees", "woods" => "trees",
    "hiking_area" => "wooded paths",
    "campground" => "open ground", "picnic_ground" => "open ground",
    "playground" => "open ground",
    "botanical_garden" => "planted beds", "garden" => "planted beds",
    "lake" => "water", "beach" => "water", "marina" => "water",
    "scenic_spot" => "a long view", "observation_deck" => "a long view",
    "mountain_peak" => "higher ground",
    "farmers_market" => "market stalls", "flea_market" => "market stalls",
    "market" => "market stalls",
    "bakery" => "a place to stop", "cafe" => "a place to stop",
    "ice_cream_shop" => "a place to stop", "dessert_shop" => "a place to stop"
  }.freeze

  CLOSING_LINES = {
    calm: "Mostly quiet streets in between.",
    refresh: "Open air most of the way.",
    cheerful: "A few things to look at along the way.",
    recharge: "Green space, and wider paths."
  }.freeze

  GENERIC_DESCRIPTION = "A short walk through the streets nearby."

  def self.fallback_for(theme_key:, waypoints:)
    features = Array(waypoints).filter_map { |wp| FEATURE_NOUNS[wp[:category].to_s] }.uniq.first(3)
    return GENERIC_DESCRIPTION if features.empty?

    listed = features.to_sentence(two_words_connector: " and ", last_word_connector: " and ")
    ["A walk past #{listed}.", CLOSING_LINES[theme_key.to_sym]].compact.join(" ")
  end

  def initialize(theme_key:, waypoints:, target_distance_meters: nil)
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
    @waypoints = Array(waypoints)
    @target_distance_meters = target_distance_meters
  end

  def call
    return empty_result("No waypoints to describe") if @waypoints.empty?

    fields = request_llm
    Result.new(success?: true, description: fields["description"], error: nil)
  rescue StandardError => e
    empty_result(e.message)
  end

  private

  # RubyLLM 2.0 moved structured output to Message#parsed; #content is now the
  # raw JSON string. Reading a key off that string returns the key back --
  # "{\"quote\":\"...\"}"["quote"] is "quote" -- so this failed quietly rather
  # than raising, handing back the field name as the answer.
  def request_llm
    LlmChat.with_chat do |chat|
      chat.with_instructions(SYSTEM_PROMPT)
          .with_schema(DescriptionSchema)
          .ask(user_message)
          .parsed
    end
  end

  def user_message
    <<~MSG
      Theme: #{@theme[:label]}
      Tone: #{@theme[:tone]}
      #{target_distance_line}
      Places on this walk, in order:
      #{waypoints_as_json}
    MSG
  end

  def target_distance_line
    return "" if @target_distance_meters.blank?

    "Target walk distance: about #{@target_distance_meters.round} meters round trip.\n"
  end

  def waypoints_as_json
    @waypoints.map { |poi| poi.slice(:id, :name, :category, :distance_meters) }.to_json
  end

  def empty_result(error_message)
    Result.new(success?: false, description: nil, error: error_message)
  end
end
