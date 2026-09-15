RubyLLM.configure do |config|
  # Which model and provider are used lives in LlmChat, not here -- these are
  # only credentials. Keys for providers the app is not currently pointed at
  # are harmless, and mean switching back is a one-line change in LlmChat.
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end
