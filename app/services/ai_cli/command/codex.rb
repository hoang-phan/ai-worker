require "json"

module AiCli
  class Command
    # Builds Codex's argv. Codex accepts MCP settings only as TOML overrides,
    # which must appear between `exec` and the execution flags/prompt.
    class Codex
      def initialize(prompt:, mcp_config:, model: nil, effort: nil, mcp_servers: Command.method(:mcp_servers))
        @prompt = prompt
        @mcp_config = mcp_config
        @model = model
        @effort = effort
        @mcp_servers = mcp_servers
      end

      def to_a
        [ "codex", "exec", *mcp_overrides, *effort_override,
          "--dangerously-bypass-approvals-and-sandbox", *model_option, prompt ]
      end

      private

      attr_reader :prompt, :mcp_config, :model, :effort, :mcp_servers

      def model_option
        model.present? ? [ "--model", model.to_s ] : []
      end

      # Codex takes reasoning effort through its TOML configuration rather
      # than an execution flag, e.g. -c 'model_reasoning_effort="high"'.
      def effort_override
        effort.present? ? [ "-c", "model_reasoning_effort=#{effort.to_s.to_json}" ] : []
      end

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
