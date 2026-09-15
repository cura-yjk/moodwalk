require "test_helper"

# The prose on every route card. RouteBuilder no longer waits on this -- a
# journey is saved with fallback_for and JourneyDescriptionJob replaces it --
# so both paths have to hold up on their own.
class RouteDescriberTest < ActiveSupport::TestCase
  WAYPOINTS = [
    { id: "p1", name: "Meguro River", category: "park", distance_meters: 400 },
    { id: "p2", name: "Aoi Bakery", category: "bakery", distance_meters: 700 }
  ].freeze

  # --- the written description -------------------------------------------

  test "returns the written description" do
    stub_llm(description: "A walk beside the water, then quieter streets.")

    result = RouteDescriber.new(theme_key: :calm, waypoints: WAYPOINTS).call

    assert result.success?
    assert_equal "A walk beside the water, then quieter streets.", result.description
  end

  test "sends the theme's tone and the chosen places, in walking order" do
    stub_llm(description: "x")

    RouteDescriber.new(theme_key: :calm, waypoints: WAYPOINTS, target_distance_meters: 2_400).call

    assert_requested :post, llm_url do |request|
      sent = request.body
      sent.include?(THEMES[:calm][:tone].split(" — ").first) &&
        sent.include?("Meguro River") && sent.index("Meguro River") < sent.index("Aoi Bakery") &&
        sent.include?("2400")
    end
  end

  test "a route with nothing on it is not described" do
    RouteDescriber.new(theme_key: :calm, waypoints: []).call.tap do |result|
      assert_not result.success?
      assert_match(/no waypoints/i, result.error)
    end

    assert_not_requested :post, llm_url
  end

  test "an unknown theme is refused before any request is made" do
    assert_raises(ArgumentError) { RouteDescriber.new(theme_key: :nonsense, waypoints: WAYPOINTS) }
    assert_not_requested :post, llm_url
  end

  # Losing the prose must cost the prose, not the walk.
  test "an LLM failure comes back as a failed result rather than raising" do
    stub_request(:post, llm_url).to_return(status: 500, body: "{}")

    result = RouteDescriber.new(theme_key: :calm, waypoints: WAYPOINTS).call

    assert_not result.success?
    assert result.error.present?
  end

  # --- the fallback, which is what a saved journey actually starts with ---

  test "the fallback describes what is there without naming any of it" do
    description = RouteDescriber.fallback_for(theme_key: :calm, waypoints: WAYPOINTS)

    assert_match "trees", description
    assert_match "a place to stop", description
    WAYPOINTS.each do |waypoint|
      assert_no_match(/#{waypoint[:name]}/, description,
                      "naming a place turns 'just walk' into 'go find this'")
    end
  end

  test "the fallback obeys the tone rules the prompt sets" do
    THEMES.each_key do |theme|
      description = RouteDescriber.fallback_for(theme_key: theme, waypoints: WAYPOINTS)

      assert description.present?, "#{theme} produced no description"
      assert_no_match(/!/, description, "#{theme} used an exclamation point")
      assert_no_match(/\byou\b/i, description, "#{theme} addressed the reader")
      assert_no_match(/push|challenge|deserve|don't miss|make the most/i, description,
                      "#{theme} used pressure framing")
    end
  end

  test "the fallback does not repeat a feature two waypoints share" do
    waypoints = [
      { id: "a", name: "A", category: "park", distance_meters: 100 },
      { id: "b", name: "B", category: "city_park", distance_meters: 200 }
    ]

    assert_equal 1, RouteDescriber.fallback_for(theme_key: :calm, waypoints: waypoints).scan("trees").size
  end

  test "the fallback still says something when nothing maps to a feature" do
    waypoints = [{ id: "a", name: "A", category: "not_a_real_type", distance_meters: 100 }]

    assert_equal RouteDescriber::GENERIC_DESCRIPTION,
                 RouteDescriber.fallback_for(theme_key: :calm, waypoints: waypoints)
    assert_equal RouteDescriber::GENERIC_DESCRIPTION,
                 RouteDescriber.fallback_for(theme_key: :calm, waypoints: [])
  end

  # Every category in themes.rb must map to a feature noun, or a route built
  # from it falls back to the generic line for no reason.
  test "every theme category the app can select has something to say about it" do
    THEMES.each do |theme, config|
      config[:categories].each do |category|
        assert RouteDescriber::FEATURE_NOUNS.key?(category),
               "#{theme}'s #{category} has no entry in FEATURE_NOUNS"
      end
    end
  end

  private

  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm(description:)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { description: description }.to_json }] } }]
      }.to_json)
  end
end
