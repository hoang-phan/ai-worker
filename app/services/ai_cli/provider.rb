module AiCli
  # One agent CLI (claude, cursor, codex, ...): what it supports, how its argv is built, how a run is prepared and
  # how a finished run is judged. Stateless; see Providers for the registry. To support another CLI, add a subclass
  # and register it there. Per-run options a provider has no flag for are ignored, so callers consult
  # `capabilities` and compensate in the prompt.
  class Provider
    # tool_lists: honours allowed/disallowed tool lists. model / effort: honours them. mcp: how an extra MCP config
    # reaches the agent, :flag, :overrides (codex `-c` settings) or :file (written into the project for the run).
    Capabilities = Data.define(:tool_lists, :model, :effort, :mcp)

    attr_reader :name, :capabilities

    def initialize(name:, capabilities:)
      @name = name
      @capabilities = capabilities
    end

    # The Command builder (responds to `to_a`) for one run. Options the provider does not use are ignored.
    def builder(**)
      raise NotImplementedError, "#{self.class} must build its argv"
    end

    # Final argv for the spawn; override to set the run up and tear it down around the command.
    def wrap(command, project_directory:, mcp_config:)
      command
    end

    # :success / :error / nil (unknown) from the log of a finished run, for when the exit status was lost.
    def outcome(_output)
      nil
    end
  end
end
