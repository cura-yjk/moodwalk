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

  def initialize(theme_key:, waypoints:, target_distance_meters: nil)
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
    @waypoints = Array(waypoints)
    @target_distance_meters = target_distance_meters
  end

  def call
    return empty_result("No waypoints to describe") if @waypoints.empty?

    parsed = request_llm
    Result.new(success?: true, description: parsed["description"], error: nil)
  rescue StandardError => e
    empty_result(e.message)
  end

  private

  def request_llm
    chat = RubyLLM.chat
                  .with_instructions(SYSTEM_PROMPT)
                  .with_schema(DescriptionSchema)

    chat.ask(user_message).content
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
