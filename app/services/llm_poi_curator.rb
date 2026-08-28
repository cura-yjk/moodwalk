require "ruby_llm/schema" # gem 'ruby_llm-schema'

class LlmPoiCurator
  Result = Struct.new(:success?, :waypoints, :description, :error, keyword_init: true)

  class SelectionSchema < RubyLLM::Schema
    array :selected_poi_ids, of: :string,
                             description: "2-4 ids from the provided candidate list, in walking order"
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

    Given a theme and a list of real nearby places, select 2-4 of them that
    best fit the walk, put them in a sensible walking order, and write a
    short description of the route.
  PROMPT

  def initialize(theme_key:, pois:)
    @theme_key = theme_key.to_sym
    @theme = THEMES.fetch(@theme_key) { raise ArgumentError, "Unknown theme: #{theme_key}" }
    @pois = Array(pois)
  end

  def call
    return empty_result("No nearby places found") if @pois.empty?

    parsed = request_llm
    waypoints = resolve_waypoints(parsed["selected_poi_ids"])

    return empty_result("LLM did not select any valid places") if waypoints.empty?

    Result.new(success?: true, waypoints: waypoints, description: parsed["description"], error: nil)
  rescue StandardError => e
    empty_result(e.message)
  end

  private

  def request_llm
    chat = RubyLLM.chat
                  .with_instructions(SYSTEM_PROMPT)
                  .with_schema(SelectionSchema)

    chat.ask(user_message)
  end

  def user_message
    <<~MSG
      Theme: #{@theme[:label]}
      Tone: #{@theme[:tone]}

      Nearby places found:
      #{poi_list_as_json}
    MSG
  end

  def poi_list_as_json
    @pois.map { |poi| poi.slice(:id, :name, :category) }.to_json
  end

  # Silently drops any id that doesn't match a real candidate (defensive --
  # schema doesn't guarantee the ids are ones we actually sent).
  def resolve_waypoints(selected_ids)
    return [] if selected_ids.blank?

    pois_by_id = @pois.index_by { |poi| poi[:id] }
    selected_ids.filter_map { |id| pois_by_id[id] }
  end

  def empty_result(error_message)
    Result.new(success?: false, waypoints: [], description: nil, error: error_message)
  end
end
