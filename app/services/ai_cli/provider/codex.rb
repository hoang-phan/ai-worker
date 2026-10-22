module AiCli
  class Provider
    class Codex < Provider
      def initialize
        super(name: "codex", capabilities: Capabilities.new(tool_lists: false, model: true, effort: true, mcp: :overrides))
      end

      def builder(prompt:, mcp_config: nil, model: nil, effort: nil, **)
        Command::Codex.new(prompt: prompt, mcp_config: mcp_config, model: model, effort: effort)
      end
    end
  end
end
