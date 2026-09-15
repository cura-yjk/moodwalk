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

  # Plain-Ruby stand-in for when the LLM is unavailable, so the memory card
  # shows something rather than an empty space. Obeys the same rules as
  # SYSTEM_PROMPT: short, plain, never falsely cheerful, no pressure or guilt,
  # no place names -- and, critically, it invents nothing. It only ever
  # restates the moods the user logged themselves, which is what the prompt
  # tells the model to fall back on when a reflection is too short to use.
  QUOTE_BY_MOOD_AFTER = {
    "Calm" => "The walk ended quieter than it started.",
    "Good" => "A steadier finish than the start.",
    "Energised" => "Moving helped.",
    "Neutral" => "A walk, and then the rest of the day.",
    "Stressed" => "Not every walk settles things. This one still happened."
  }.freeze

  GENERIC_QUOTE = "A walk, start to finish."

  def self.fallback_for(mood_before:, mood_after:)
    return QUOTE_BY_MOOD_AFTER.fetch(mood_after, GENERIC_QUOTE) if mood_before.blank? ||
                                                                   mood_after.blank? ||
                                                                   mood_before == mood_after

    "Set out #{mood_before.downcase}. Finished #{mood_after.downcase}."
  end

  def initialize(reflection:, mood_before:, mood_after:)
    @reflection = reflection.to_s
    @mood_before = mood_before
    @mood_after = mood_after
  end

  def call
    parsed = request_llm
    Result.new(success?: true, quote: parsed.content["quote"])
  rescue StandardError => e
    Result.new(success?: false, error: e.message)
  end

  private

  def request_llm
    LlmChat.with_chat do |chat|
      chat.with_instructions(SYSTEM_PROMPT)
          .with_schema(QuoteSchema)
          .ask(user_message)
    end
  end

  def user_message
    <<~MSG
      Mood before the walk: #{@mood_before || 'unknown'}
      Mood after the walk: #{@mood_after || 'unknown'}
      Reflection written: #{@reflection.presence || '(nothing written)'}
    MSG
  end
end
