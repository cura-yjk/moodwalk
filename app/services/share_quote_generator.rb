require "ruby_llm/schema"

class ShareQuoteGenerator
  Result = Struct.new(:success?, :quote, :error, keyword_init: true)

  class QuoteSchema < RubyLLM::Schema
    string :quote, description: "1-2 sentence atmospheric quote, grounded only in what was given"
  end

  SYSTEM_PROMPT = <<~PROMPT
    You turn a short personal walk journal entry into a single atmospheric
    quote for a share card, for a mood-support app used by people who are
    often physically, emotionally, or mentally overwhelmed.

    Rules:
    - Write 1-2 short sentences. No more.
    - Use plain, concrete, sensory language - not abstract mood language.
    - Never use exclamation points. Never sound falsely cheerful or upbeat.
    - Never use pressure, achievement, or challenge framing.
    - Never use guilt, urgency, or scarcity language.
    - Ground the quote only in what the person actually wrote - do not
      invent details, places, or events they didn't mention.
    - Do not name specific places or streets.
    - If the reflection is empty or too short to work with, write a quote
      based only on the shift from mood_before to mood_after.
  PROMPT

  def initialize(reflection:, mood_before:, mood_after:)
    @reflection = reflection.to_s
    @mood_before = mood_before
    @mood_after = mood_after
  end

  def call
    parsed = request_llm
    Result.new(success?: true, quote: parsed["quote"])
  rescue StandardError => e
    Result.new(success?: false, error: e.message)
  end

  private

  def request_llm
    chat = RubyLLM.chat
                  .with_instructions(SYSTEM_PROMPT)
                  .with_schema(QuoteSchema)

    chat.ask(user_message)
  end

  def user_message
    <<~MSG
      Mood before the walk: #{@mood_before || 'unknown'}
      Mood after the walk: #{@mood_after || 'unknown'}
      Reflection written: #{@reflection.presence || '(nothing written)'}
    MSG
  end
end
