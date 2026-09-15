require "test_helper"

# Each Gemini key carries its own small free-tier quota, so one exhausted key
# would take route descriptions, highlights and share quotes down together.
class LlmChatTest < ActiveSupport::TestCase
  setup do
    @original = ENV.fetch("GEMINI_API_KEYS", nil)
    ENV["GEMINI_API_KEYS"] = "first-key,second-key"
  end

  teardown { ENV["GEMINI_API_KEYS"] = @original }

  test "reads every configured key, trimming whitespace" do
    ENV["GEMINI_API_KEYS"] = " first-key , second-key ,"

    assert_equal %w[first-key second-key], LlmChat.keys
  end

  test "falls back to the single-key variable" do
    ENV["GEMINI_API_KEYS"] = nil

    assert_equal [ENV.fetch("GEMINI_API_KEY")], LlmChat.keys
  end

  test "moves to the next key when the first is out of quota" do
    stub_key("first-key", status: 429, body: { error: { message: "quota" } }.to_json)
    stub_key("second-key", status: 200, body: reply_body("ok"))

    answer = LlmChat.with_chat { |chat| chat.ask("hello") }

    assert_equal "ok", answer.content
    assert_requested :post, generate_url, headers: { "X-Goog-Api-Key" => "second-key" }, at_least_times: 1
  end

  test "raises once every key is exhausted" do
    stub_key("first-key", status: 429, body: { error: { message: "quota" } }.to_json)
    stub_key("second-key", status: 429, body: { error: { message: "quota" } }.to_json)

    assert_raises(RubyLLM::RateLimitError) { LlmChat.with_chat { |chat| chat.ask("hello") } }
  end

  # A bad request fails the same way on any key, and retrying it would spend a
  # second key's budget to produce the same error.
  test "does not spend another key on an error that is not about quota" do
    stub_key("first-key", status: 400, body: { error: { message: "bad request" } }.to_json)
    stub_key("second-key", status: 200, body: reply_body("ok"))

    assert_raises(RubyLLM::BadRequestError) { LlmChat.with_chat { |chat| chat.ask("hello") } }
    assert_not_requested :post, generate_url, headers: { "X-Goog-Api-Key" => "second-key" }
  end

  private

  def generate_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_key(key, status:, body:)
    stub_request(:post, generate_url)
      .with(headers: { "X-Goog-Api-Key" => key })
      .to_return(status: status, headers: { "Content-Type" => "application/json" }, body: body)
  end

  def reply_body(text)
    { "candidates" => [{ "content" => { "parts" => [{ "text" => text }] } }] }.to_json
  end
end
