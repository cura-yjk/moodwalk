require "test_helper"

# The line on a walk's share card. Both paths matter: the LLM writes it when it
# can, and the fallback is what a card shows when it cannot.
class ShareQuoteGeneratorTest < ActiveSupport::TestCase
  test "returns the written quote" do
    stub_llm(quote: "The river was louder than the road.")

    result = ShareQuoteGenerator.new(reflection: "walked by the river", mood_before: "Stressed",
                                     mood_after: "Calm").call

    assert result.success?
    assert_equal "The river was louder than the road.", result.quote
  end

  test "sends the moods and what the person actually wrote" do
    stub_llm(quote: "x")

    ShareQuoteGenerator.new(reflection: "felt the wind", mood_before: "Stressed", mood_after: "Calm").call

    assert_requested :post, llm_url do |request|
      request.body.include?("felt the wind") && request.body.include?("Stressed") &&
        request.body.include?("Calm")
    end
  end

  test "an empty reflection still asks, with the moods to work from" do
    stub_llm(quote: "x")

    ShareQuoteGenerator.new(reflection: "", mood_before: "Stressed", mood_after: "Calm").call

    assert_requested :post, llm_url do |request|
      request.body.include?("nothing written")
    end
  end

  test "an LLM failure comes back as a failed result rather than raising" do
    stub_request(:post, llm_url).to_return(status: 500, body: "{}")

    result = ShareQuoteGenerator.new(reflection: "x", mood_before: "Calm", mood_after: "Calm").call

    assert_not result.success?
    assert result.error.present?
  end

  # --- the fallback ------------------------------------------------------

  test "the fallback names the shift the person logged themselves" do
    quote = ShareQuoteGenerator.fallback_for(mood_before: "Stressed", mood_after: "Calm")

    assert_match(/stressed/i, quote)
    assert_match(/calm/i, quote)
  end

  test "a walk that changed nothing is not told that it did" do
    quote = ShareQuoteGenerator.fallback_for(mood_before: "Calm", mood_after: "Calm")

    assert_equal ShareQuoteGenerator::QUOTE_BY_MOOD_AFTER.fetch("Calm"), quote
  end

  test "an unlogged mood still gets a line" do
    assert ShareQuoteGenerator.fallback_for(mood_before: nil, mood_after: "Good").present?
    assert ShareQuoteGenerator.fallback_for(mood_before: "Good", mood_after: nil).present?
    assert_equal ShareQuoteGenerator::GENERIC_QUOTE,
                 ShareQuoteGenerator.fallback_for(mood_before: nil, mood_after: nil)
  end

  # A walk that ended badly is the one most likely to be read by someone who
  # needs it not to be chirpy at them.
  test "the fallback never tells anyone how the walk should have gone" do
    Walk::MOODS.product(Walk::MOODS).each do |before, after|
      quote = ShareQuoteGenerator.fallback_for(mood_before: before, mood_after: after)

      assert quote.present?, "#{before} -> #{after} produced nothing"
      assert_no_match(/!/, quote, "#{before} -> #{after} used an exclamation point")
      assert_no_match(/should|deserve|at least|but |try |next time/i, quote,
                      "#{before} -> #{after} editorialised about the walk")
    end
  end

  test "every mood a walk can end on has a line of its own" do
    Walk::MOODS.each do |mood|
      assert ShareQuoteGenerator::QUOTE_BY_MOOD_AFTER.key?(mood),
             "#{mood} falls through to the generic quote"
    end
  end

  private

  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm(quote:)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { quote: quote }.to_json }] } }]
      }.to_json)
  end
end
