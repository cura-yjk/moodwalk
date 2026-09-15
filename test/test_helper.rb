ENV["RAILS_ENV"] ||= "test"

# Pinned before the app boots, because config/initializers/ruby_llm.rb reads it
# at load time and dotenv will not overwrite an already-set variable.
#
# RubyLLM refuses to build a request without a key for the configured provider, so with no key configured
# it raises before any HTTP call and the WebMock stubs are never reached --
# which made the LLM tests pass locally (where .env has a key) and fail in CI.
# Forcing a dummy value also guarantees the suite can never spend a real one.
# GEMINI_API_KEYS is the one LlmChat reads first, so pinning only the singular
# left the suite running on whatever real keys .env happened to hold -- one
# unstubbed request away from spending production quota. The failure that
# showed it printed a live key into the test output.
ENV["GEMINI_API_KEYS"] = "test-gemini-key-not-a-real-credential"
ENV["GEMINI_API_KEY"] = "test-gemini-key-not-a-real-credential"
ENV["ANTHROPIC_API_KEY"] = "test-anthropic-key-not-a-real-credential"
ENV["OPENAI_API_KEY"] = "test-openai-key-not-a-real-credential"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
