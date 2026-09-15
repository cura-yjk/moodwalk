require "test_helper"

# The two or three lines on a journey's preview. Written in the background now
# (JourneyHighlightsJob), so a journey is always showing Journey#highlights
# until these land -- which means a failure here has to be survivable.
class JourneyHighlightsGeneratorTest < ActiveSupport::TestCase
  setup { @journey = journeys(:meguro_loop) }

  test "returns the written highlights" do
    stub_llm([{ icon: "🌊", text: "water most of the way" }, { icon: "🌳", text: "trees at the turn" }])

    result = JourneyHighlightsGenerator.new(journey: @journey).call

    assert result.success?
    assert_equal [{ icon: "🌊", text: "Water most of the way" },
                  { icon: "🌳", text: "Trees at the turn" }], result.highlights
  end

  test "sends the journey's theme, tags and description" do
    stub_llm([{ icon: "🌳", text: "trees" }])

    JourneyHighlightsGenerator.new(journey: @journey).call

    assert_requested :post, llm_url do |request|
      request.body.include?(@journey.theme_key) && request.body.include?(@journey.description)
    end
  end

  test "a journey with no description still asks, rather than sending an empty line" do
    @journey.update!(description: nil)
    stub_llm([{ icon: "🌳", text: "trees" }])

    JourneyHighlightsGenerator.new(journey: @journey).call

    assert_requested :post, llm_url do |request|
      request.body.include?("(none provided)")
    end
  end

  # The preview shows two or three. More would overflow the card.
  test "never returns more than three, however many come back" do
    stub_llm(5.times.map { |i| { icon: "🌳", text: "highlight #{i}" } })

    assert_equal 3, JourneyHighlightsGenerator.new(journey: @journey).call.highlights.size
  end

  test "fewer than three is fine" do
    stub_llm([{ icon: "🌳", text: "only one" }])

    assert_equal 1, JourneyHighlightsGenerator.new(journey: @journey).call.highlights.size
  end

  test "text is capitalised for the card, whatever case it arrives in" do
    stub_llm([{ icon: "🌳", text: "quiet under the trees" }])

    assert_equal "Quiet under the trees",
                 JourneyHighlightsGenerator.new(journey: @journey).call.highlights.first[:text]
  end

  # The job keeps the fallback highlights on screen when this fails, so it must
  # report failure rather than raise or hand back something half-built.
  test "an LLM failure comes back as a failed result rather than raising" do
    stub_request(:post, llm_url).to_return(status: 500, body: "{}")

    result = JourneyHighlightsGenerator.new(journey: @journey).call

    assert_not result.success?
    assert result.error.present?
    assert_nil result.highlights
  end

  test "an empty answer is not a crash" do
    stub_llm([])

    result = JourneyHighlightsGenerator.new(journey: @journey).call

    assert result.success?
    assert_equal [], result.highlights
  end

  private

  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm(highlights)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { highlights: highlights }.to_json }] } }]
      }.to_json)
  end
end
