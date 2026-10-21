module AiCli
  # The app-wide agent, resolved on every call so a change takes effect on
  # the next run without a restart. Stored in Rails.cache (shared by the web
  # and Sidekiq processes, so it needs a cross-process store such as
  # file_store); falls back to the AGENT env var, then claude.
  module AgentSetting
    CACHE_KEY = "ai_cli/agent".freeze

    module_function

    def current
      cached = Rails.cache.read(CACHE_KEY)
      return cached if Command::AGENTS.key?(cached)

      ENV["AGENT"].presence || "claude"
    end

    def current=(name)
      name = name.to_s
      raise ArgumentError, "unknown agent #{name.inspect} (expected one of #{available.join(", ")})" unless Command::AGENTS.key?(name)

      Rails.cache.write(CACHE_KEY, name)
    end

    def available
      Command::AGENTS.keys
    end
  end
end
