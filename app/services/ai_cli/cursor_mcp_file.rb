require "json"
require "fileutils"

module AiCli
  # cursor reads project MCP servers from <cwd>/.cursor/mcp.json. Write the run's servers there (keeping any
  # existing file aside), keep it out of git, and have a tiny shell wrapper put things back when the run ends.
  class CursorMcpFile
    EXCLUDE_LINES = ".cursor/mcp.json\n.cursor/mcp.json.ai-worker-bak\n".freeze
    RESTORE_SCRIPT = 'trap \'rm -f "$0"; [ -f "$0.ai-worker-bak" ] && mv "$0.ai-worker-bak" "$0"\' EXIT; "$@"'.freeze

    def initialize(project_directory, mcp_config)
      @project_directory = project_directory
      @mcp_config = mcp_config
    end

    # Writes the file and returns cmd wrapped so the original file is restored when the run ends.
    def wrap(cmd)
      dir = File.join(project_directory, ".cursor")
      file = File.join(dir, "mcp.json")
      backup = "#{file}.ai-worker-bak"
      FileUtils.mkdir_p(dir)
      FileUtils.mv(file, backup) if File.exist?(file) && !File.exist?(backup)
      File.write(file, JSON.pretty_generate(mcpServers: Command.mcp_servers(mcp_config)))
      exclude_from_git

      [ "sh", "-c", RESTORE_SCRIPT, file, *cmd ]
    end

    private

    attr_reader :project_directory, :mcp_config

    def exclude_from_git
      exclude = File.join(project_directory, ".git", "info", "exclude")
      return unless File.directory?(File.dirname(exclude))

      current = File.exist?(exclude) ? File.read(exclude) : ""
      return if current.include?(".cursor/mcp.json")

      File.write(exclude, current + (current.end_with?("\n") || current.empty? ? "" : "\n") + EXCLUDE_LINES)
    end
  end
end
