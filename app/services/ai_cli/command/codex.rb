require "json"

module AiCli
  class Command
    # Builds Codex's argv. Codex accepts MCP settings only as TOML overrides,
    # which must appear between `exec` and the execution flags/prompt.
    class Codex
      def initialize(prompt:, mcp_config:, mcp_servers: Command.method(:mcp_servers))
        @prompt = prompt
        @mcp_config = mcp_config
        @mcp_servers = mcp_servers
      end

      def to_a
        [ "codex", "exec", *mcp_overrides, "--dangerously-bypass-approvals-and-sandbox", prompt ]
      end

      private

      attr_reader :prompt, :mcp_config, :mcp_servers

      def mcp_overrides
        return [] unless mcp_config.present?

        mcp_servers.call(mcp_config).flat_map do |name, server|
          overrides = { "command" => server["command"].to_json, "startup_timeout_sec" => 90 }
          overrides["args"] = Array(server["args"]).to_json if server["args"]
          overrides["env"] = "{" + server["env"].map { |key, value| "#{key.to_json} = #{value.to_json}" }.join(", ") + "}" if server["env"].present?
          overrides.flat_map { |key, value| [ "-c", "mcp_servers.#{name}.#{key}=#{value}" ] }
        end
      end
    end
  end
end
