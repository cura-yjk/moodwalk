require "test_helper"

class JourneyHighlightsJobTest < ActiveJob::TestCase
  setup do
    @journey = journeys(:meguro_loop)
    @journey.update!(highlights_text: nil)
  end

  test "writes the highlights the model returns" do
    stub_llm_success([{ icon: "🌸", text: "Cherry trees the whole way" }])

    JourneyHighlightsJob.perform_now(@journey)

    written = @journey.reload.highlights_text
    assert_equal "Cherry trees the whole way", written.first["text"]
    assert_equal "🌸", written.first["icon"]
  end

  # Two people opening the same journey at once queue two of these, and a
  # second LLM call would cost the same and produce the same thing.
  test "does nothing when the highlights are already written" do
    @journey.update!(highlights_text: [{ "icon" => "🌿", "text" => "Already here" }])

    JourneyHighlightsJob.perform_now(@journey)

    assert_not_requested :post, llm_url
    assert_equal "Already here", @journey.reload.highlights_text.first["text"]
  end

  # The page is already showing highlights derived from the route, so a failure
  # here costs nobody anything -- it must not retry or raise.
  test "leaves the fallback in place when the model cannot be reached" do
    stub_llm_failure

    assert_nothing_raised { JourneyHighlightsJob.perform_now(@journey) }

    assert_nil @journey.reload.highlights_text
  end

  # A journey can be deleted between the page asking for highlights and the job
  # running, and a job that raises for that would retry until it gave up.
  test "gives up on a journey that has been deleted" do
    JourneyHighlightsJob.perform_later(@journey)
    @journey.walks.destroy_all
    @journey.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
  end

  private

  # Follows LlmChat, so switching provider does not silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm_success(highlights)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { highlights: highlights }.to_json }] } }]
      }.to_json)
  end

  def stub_llm_failure
    stub_request(:post, llm_url)
      .to_return(status: 429, headers: { "Content-Type" => "application/json" }, body: {
        "error" => { "message" => "You have no credits remaining." }
      }.to_json)
  end
end
