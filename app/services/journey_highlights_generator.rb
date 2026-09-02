# app/services/journey_highlights_generator.rb
require "ruby_llm/schema"

class JourneyHighlightsGenerator
  Result = Struct.new(:success?, :highlights, :error, keyword_init: true)

  class HighlightsSchema < RubyLLM::Schema
    array :highlights, description: "2-3 short highlights about this walking route" do
      object do
        string :icon, description: "A single emoji representing this highlight"
        string :text, description: "3-5 word phrase describing this highlight"
      end
    end
  end

  SYSTEM_PROMPT = <<~PROMPT
    You turn a short walking-route description into 2-3 highlight phrases
    for a route preview screen, for a mood-support app used by people who
    are often physically, emotionally, or mentally overwhelmed.

    Rules:
    - Return 2-3 highlights, no more.
    - Each highlight pairs one emoji with a 3-5 word phrase.
    - Use plain, concrete, sensory language - not abstract mood language.
    - Never use exclamation points. Never sound falsely cheerful or upbeat.
    - Never use pressure, achievement, or challenge framing (no "push
      yourself", "great workout", step counts, calorie or fitness framing).
    - Ground each highlight only in what was actually given - do not invent
      specific places, landmarks, or details not implied by the description
      or tags.
    - If the description is too sparse to support 2-3 distinct highlights,
      it's fine to return fewer, or to lean on the theme's general tone.
  PROMPT

  def initialize(journey:)
    @journey = journey
  end

  def call
    parsed = request_llm
    Result.new(success?: true, highlights: normalize(parsed.content["highlights"]))
  rescue StandardError => e
    Result.new(success?: false, error: e.message)
  end

  private

  def request_llm
    chat = RubyLLM.chat
                  .with_instructions(SYSTEM_PROMPT)
                  .with_schema(HighlightsSchema)

    chat.ask(user_message)
  end

  def user_message
    <<~MSG
      Theme: #{@journey.theme_key.presence || 'none'}
      Tags: #{@journey.tags.join(', ')}
      Description: #{@journey.description.presence || '(none provided)'}
    MSG
  end

  def normalize(highlights)
    Array(highlights).first(3).map { |h| { icon: h["icon"], text: h["text"].to_s.capitalize } }
  end
end
