# app/services/llm_poi_curator.rb
#
# Given a theme and a list of real nearby POIs (PoiFinder's output), asks
# the LLM to:
#   1. select 2-4 of the real candidate POIs that fit the theme
#   2. put them in a sensible walking order
#   3. write a short, grounded description of the route
#
# Uses RubyLLM's structured output (`with_schema`) instead of hand-rolled
# JSON parsing, so the shape of the response is guaranteed rather than
# hoped for.
#
# Usage:
#   poi_result = PoiFinder.new(lat:, lng:, categories: THEMES[:nature_escape][:categories]).call
#   curation   = LlmPoiCurator.new(theme_key: :nature_escape, pois: poi_result.pois).call
#
#   if curation.success?
#     curation.waypoints    # => [{ id:, name:, category:, lat:, lng: }, ...] in walking order
#     curation.description  # => "..."
#   else
#     curation.error
#   end

class LlmPoiCurator
  Result = Struct.new(:success?, :waypoints, :description, :error, keyword_init: true)

  # Structured output schema — guarantees the LLM returns exactly this
  # shape instead of us parsing free-text JSON.
  class SelectionSchema < RubyLLM::Schema
    array :selected_poi_ids, of: :string,
                             description: "2-4 ids from the provided candidate list, in walking order"
    string :description,
           description: "1-2 sentence route description, grounded only in the selected places"
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

  # Only send the LLM what it needs to choose and order — not lat/lng,
  # which it has no use for and could hallucinate around.
  def poi_list_as_json
    @pois.map { |poi| poi.slice(:id, :name, :category) }.to_json
  end

  # Map the LLM's chosen ids back to full POI hashes (with real lat/lng),
  # preserving the order the LLM chose, and silently dropping any id that
  # doesn't match a real candidate (defensive — schema doesn't guarantee
  # the ids are ones we actually sent).
  def resolve_waypoints(selected_ids)
    return [] if selected_ids.blank?

    pois_by_id = @pois.index_by { |poi| poi[:id] }
    selected_ids.filter_map { |id| pois_by_id[id] }
  end

  def empty_result(error_message)
    Result.new(success?: false, waypoints: [], description: nil, error: error_message)
  end
end
