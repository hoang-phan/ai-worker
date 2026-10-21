module AiCli
  class Command
    # Builds the Claude-specific argv. Claude is the only supported agent with
    # per-run tool, model, effort, and verbose-output flags.
    class Claude
      def initialize(prompt:, allowed_tools:, mcp_config:, disallowed_tools:, model:, effort:, verbose:)
        @prompt = prompt
        @allowed_tools = allowed_tools
        @mcp_config = mcp_config
        @disallowed_tools = disallowed_tools
        @model = model
        @effort = effort
        @verbose = verbose
      end

      def to_a
        command = [ "claude", "-p", prompt, *permission_args ]
        command += [ "--mcp-config", mcp_config.to_s ] if mcp_config.present?
        command += [ "--disallowedTools", *disallowed_tools ] if disallowed_tools.present?
        command += [ "--model", model.to_s ] if model.present?
        command += [ "--effort", effort.to_s ] if effort.present?
        command += [ "--output-format", "stream-json", "--verbose", "--include-partial-messages" ] if verbose
        command
      end

      private

      attr_reader :prompt, :allowed_tools, :mcp_config, :disallowed_tools, :model, :effort, :verbose

      def permission_args
        allowed_tools.present? ? [ "--allowedTools", *allowed_tools ] : [ "--dangerously-skip-permissions" ]
      end
    end
  end
end
