module AiCli
  # Registry of the supported agent CLIs, in display order.
  module Providers
    ALL = [ Provider::Claude.new, Provider::Cursor.new, Provider::Codex.new ].index_by(&:name).freeze

    module_function

    def names
      ALL.keys
    end

    def find(name)
      ALL[name.to_s]
    end

    def fetch(name)
      find(name) || raise(CommandError, "unknown AGENT #{name.inspect} (expected one of #{names.join(", ")})")
    end
  end
end
