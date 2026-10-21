require "open3"

module AiCli
  class Command
    # Builds Cursor's argv and owns its two environment probes. Both are
    # dependencies so callers and specs can avoid invoking real Cursor CLIs.
    class Cursor
      DEFAULT_EXECUTABLE_CHECK = lambda do |name|
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, name)
          File.executable?(path) && !File.directory?(path)
        end
      end

      DEFAULT_HELP_PROBE = lambda do |binary|
        out, _status = Open3.capture2e(binary, "--help")
        out
      rescue SystemCallError
        ""
      end

      def initialize(prompt:, mcp_config:, executable_check: DEFAULT_EXECUTABLE_CHECK, help_probe: DEFAULT_HELP_PROBE)
        @prompt = prompt
        @mcp_config = mcp_config
        @executable_check = executable_check
        @help_probe = help_probe
      end

      def to_a
        binary = binary_for_cursor
        command = [ binary, "-p", prompt, "--force" ]
        command << "--approve-mcps" if mcp_config.present? && help_probe.call(binary).to_s.include?("--approve-mcps")
        command
      end

      private

      attr_reader :prompt, :mcp_config, :executable_check, :help_probe

      # Cursor's CLI is installed as `agent` by newer versions and
      # `cursor-agent` by older ones.
      def binary_for_cursor
        [ "agent", "cursor-agent" ].find { |name| executable_check.call(name) } || "agent"
      end
    end
  end
end
