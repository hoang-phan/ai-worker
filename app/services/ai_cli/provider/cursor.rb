module AiCli
  class Provider
    class Cursor < Provider
      def initialize
        super(name: "cursor", capabilities: Capabilities.new(tool_lists: false, model: false, effort: false, mcp: :file))
      end

      def builder(prompt:, mcp_config: nil, executable_check: Command::DEFAULT_EXECUTABLE_CHECK, help_probe: Command::DEFAULT_HELP_PROBE, **)
        Command::Cursor.new(prompt: prompt, mcp_config: mcp_config, executable_check: executable_check, help_probe: help_probe)
      end

      # Cursor reads MCP servers from the project's `.cursor/mcp.json`, so the command is wrapped to write that file
      # for the length of the run.
      def wrap(command, project_directory:, mcp_config:)
        return command unless mcp_config.present?

        CursorMcpFile.new(project_directory, mcp_config).wrap(command)
      end
    end
  end
end
