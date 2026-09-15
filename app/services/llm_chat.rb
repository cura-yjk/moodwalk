# One place to say who writes the app's prose, with which model, and on which
# credentials.
#
# All three LLM features (RouteDescriber, ShareQuoteGenerator,
# JourneyHighlightsGenerator) make the same shape of call -- a short system
# prompt, a short user message, a schema-constrained answer -- so they share a
# model rather than each naming one.
module LlmChat
  MODEL = "gemini-3.5-flash"
  PROVIDER = :gemini

  module_function

  # Every configured key, in the order they should be tried.
  #
  # GEMINI_API_KEYS holds a comma-separated list so keys never reach the repo;
  # GEMINI_API_KEY is still read as a single-key fallback, which is what the
  # test environment provides.
  def keys
    list = ENV.fetch("GEMINI_API_KEYS", nil).presence || ENV.fetch("GEMINI_API_KEY", "")

    list.split(",").map(&:strip).reject(&:empty?)
  end

  # Yields a chat, and yields a fresh one on the next key if the provider says
  # the current key is out of quota.
  #
  # Quota is per key and the free tier is small -- around twenty requests -- so
  # one exhausted key would otherwise take route descriptions, highlights and
  # share quotes down together until it reset. Anything that is not a quota
  # error is raised immediately: a bad request will not succeed on different
  # credentials, and retrying it spends a second key's budget for the same
  # failure.
  #
  # The block does the whole exchange rather than just building the chat, so a
  # retry sends the instructions and schema again on the new key.
  def with_chat
    exhausted = []

    keys.each do |key|
      return yield chat_on(key)
    rescue RubyLLM::RateLimitError => e
      exhausted << e
      Rails.logger.warn("Gemini key ending #{key.last(6)} is out of quota; trying the next one")
    end

    raise exhausted.last || RubyLLM::Error.new(nil, "No Gemini API key is configured")
  end

  # A chat on one specific key. RubyLLM.context keeps the credential on the
  # chat rather than mutating RubyLLM.configure, which two requests being
  # served at once would race over.
  #
  # The version is pinned rather than using the floating "-latest" alias: a
  # model that changes under you changes the writing without a deploy.
  #
  # assume_model_exists skips ruby_llm's bundled registry, which lags behind
  # new releases. The registry only gates the name; the request is unaffected.
  def chat_on(key)
    RubyLLM.context { |config| config.gemini_api_key = key }
           .chat(model: MODEL, provider: PROVIDER, assume_model_exists: true)
  end
end
