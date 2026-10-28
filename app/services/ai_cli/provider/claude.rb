module AiCli
  class Provider
    class Claude < Provider
      def initialize
        super(name: "claude", capabilities: Capabilities.new(tool_lists: true, model: true, effort: true, mcp: :flag))
      end

      def builder(prompt:, allowed_tools: nil, mcp_config: nil, disallowed_tools: [], model: nil, effort: nil, verbose: false, **)
        Command::Claude.new(prompt: prompt, allowed_tools: allowed_tools, mcp_config: mcp_config,
                            disallowed_tools: disallowed_tools, model: model, effort: effort, verbose: verbose)
      end

      # Claude's final result event in the log says how the run ended.
      def outcome(output)
        ClaudeResult.new(output).final_outcome
      end
    end
  end
end
