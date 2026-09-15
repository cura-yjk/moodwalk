# One place to say who writes the app's prose, and with which model.
#
# All three LLM features (RouteDescriber, ShareQuoteGenerator,
# JourneyHighlightsGenerator) make the same shape of call -- a short system
# prompt, a short user message, a schema-constrained answer -- so they share a
# model rather than each naming one. Changing provider is these two constants
# plus a key in config/initializers/ruby_llm.rb; nothing else moves.
module LlmChat
  MODEL = "gemini-3.5-flash"
  PROVIDER = :gemini

  module_function

  # The version is pinned rather than using the floating "-latest" alias: a
  # model that changes under you changes the writing without a deploy.
  #
  # assume_model_exists skips ruby_llm's bundled registry, which lags behind
  # new releases. The registry only gates the name; the request is unaffected.
  def new_chat
    RubyLLM.chat(model: MODEL, provider: PROVIDER, assume_model_exists: true)
  end
end
