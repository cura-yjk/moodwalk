require "test_helper"

class JourneyDescriptionJobTest < ActiveJob::TestCase
  WAYPOINTS = [
    { id: "a", name: "Some Park", category: "park", distance_meters: 300 },
    { id: "b", name: "The Lake", category: "lake", distance_meters: 500 }
  ].freeze

  setup do
    @journey = journeys(:meguro_loop) # theme_key: calm
    @journey.update!(description: RouteDescriber.fallback_for(theme_key: :calm, waypoints: WAYPOINTS))
    @fallback = @journey.description
  end

  test "replaces the fallback description with the LLM's" do
    stub_llm_success("Water on one side, trees on the other.")

    JourneyDescriptionJob.perform_now(@journey, WAYPOINTS)

    assert_equal "Water on one side, trees on the other.", @journey.reload.description
  end

  # The route is already usable with its fallback, so a dead LLM must not
  # blank the description or raise -- it simply leaves the fallback in place.
  test "keeps the fallback when the LLM is unavailable" do
    stub_llm_failure

    assert_nothing_raised { JourneyDescriptionJob.perform_now(@journey, WAYPOINTS) }

    assert_equal @fallback, @journey.reload.description
  end

  test "survives waypoints round-tripping through ActiveJob serialization" do
    stub_llm_success("A quiet stretch of water.")

    perform_enqueued_jobs do
      JourneyDescriptionJob.perform_later(@journey, WAYPOINTS)
    end

    assert_equal "A quiet stretch of water.", @journey.reload.description
  end

  test "does nothing for an unthemed journey" do
    unthemed = journeys(:unmeasured)
    unthemed.update!(description: "Left alone.")

    JourneyDescriptionJob.perform_now(unthemed, WAYPOINTS)

    assert_equal "Left alone.", unthemed.reload.description
    assert_not_requested :post, llm_url
  end

  private

  # Follows LlmChat, so switching provider does not silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm_success(description)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { description: description }.to_json }] } }]
      }.to_json)
  end

  def stub_llm_failure
    stub_request(:post, llm_url)
      .to_return(status: 429, headers: { "Content-Type" => "application/json" }, body: {
        "error" => { "message" => "You have no credits remaining." }
      }.to_json)
  end
end
