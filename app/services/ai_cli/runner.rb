require "json"
require "fileutils"

module AiCli
  # Starts the selected agent CLI (`claude -p "<prompt>"`, `agent -p
  # "<prompt>" --force`, ...) detached from the calling process and
  # returns immediately — a run can take longer than Sidekiq's 5-minute
  # job timeout, so the job must never block on it. Output is redirected
  # to a log file on disk; WorkflowSchedulerJob polls back on a later
  # cron tick to see whether the process has finished (see
  # docs/RUNBOOK.md).
  class Runner
    AGENTS = Command::AGENTS

    # Bundler/Ruby variables describing *this* app's bundle. Left in the agent's environment they leak into whatever
    # the agent runs in the project's own clone: e.g. BUNDLER_VERSION pins the project's `bundle` to ai-worker's
    # Bundler instead of the one its Gemfile.lock asks for, BUNDLE_GEMFILE points at our Gemfile. Unset for every run.
    LEAKED_ENV = %w[
      BUNDLE_GEMFILE BUNDLE_LOCKFILE BUNDLE_BIN_PATH BUNDLER_VERSION BUNDLER_SETUP
      BUNDLER_ORIG_BUNDLE_GEMFILE BUNDLER_ORIG_BUNDLE_LOCKFILE BUNDLER_ORIG_BUNDLE_BIN_PATH
      BUNDLER_ORIG_RUBYOPT BUNDLER_ORIG_RUBYLIB BUNDLER_ORIG_PATH
      RUBYOPT RUBYLIB RAILS_ENV RACK_ENV
    ].freeze

    def self.agent = AgentSetting.current

    def self.agent=(name)
      AgentSetting.current = name
    end

    def self.available_agents = AgentSetting.available

    def self.start(project_directory, prompt, log_path:, allowed_tools: nil, mcp_config: nil, env: {}, disallowed_tools: [], model: nil, effort: nil)
      new.start(project_directory, prompt, log_path: log_path, allowed_tools: allowed_tools,
                    mcp_config: mcp_config, env: env, disallowed_tools: disallowed_tools, model: model, effort: effort)
    end

    # Non-blocking: returns :running, or [:completed, Process::Status-or-nil].
    def self.poll(pid)
      new.poll(pid)
    end

    # allowed_tools (claude only): run with exactly these tools approved
    # (`--allowedTools`) instead of skipping every permission check, for runs
    # that should be read-only, e.g. the Slack mention fetch. Anything not
    # listed is denied, since headless mode can't ask. Ignored by other agents.
    #
    # mcp_config: path of an extra MCP server config (claude's `{"mcpServers": {...}}` format) for this run, on top of
    # the user's own servers, e.g. the browser used by the UAT test. claude gets it as `--mcp-config`; codex gets
    # the servers as `-c mcp_servers.<name>.*` overrides; cursor gets them in `.cursor/mcp.json` of the project directory
    # for the length of the run. env: extra variables for the agent process.
    #
    # disallowed_tools (claude only): tool rules denied for this run only (`--disallowedTools`, e.g.
    # `Bash(gh workflow run:*)`). Deny rules win even over --dangerously-skip-permissions. Other agents have no
    # equivalent, so the prompt has to say it.
    #
    # model / effort (claude only): `--model` / `--effort` for this run instead of the CLI's defaults, e.g. a stronger
    # model for brainstorming. Other agents ignore them.
    def start(project_directory, prompt, log_path:, allowed_tools: nil, mcp_config: nil, env: {}, disallowed_tools: [], model: nil, effort: nil)
      FileUtils.mkdir_p(File.dirname(log_path))

      # `claude -p` stops background subagents 10 minutes after the last
      # turn; 0 makes it wait for them. STALE_AFTER is the real timeout.
      agent = self.class.agent
      cmd = Command.new(agent: agent, prompt: prompt, allowed_tools: allowed_tools, mcp_config: mcp_config,
                        disallowed_tools: disallowed_tools, model: model, effort: effort).to_a
      cmd = CursorMcpFile.new(project_directory, mcp_config).wrap(cmd) if agent == "cursor" && mcp_config.present?

      Process.spawn(
        LEAKED_ENV.index_with(nil).merge("CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS" => "0").merge(env.transform_values(&:to_s)),
        *cmd,
        chdir: project_directory,
        in: File::NULL,
        out: [ log_path, "a" ],
        err: [ log_path, "a" ]
      )
    end

    def poll(pid)
      _reaped_pid, status = Process.wait2(pid, Process::WNOHANG)
      status ? [ :completed, status ] : :running
    rescue Errno::ECHILD
      # Not our child anymore (e.g. the Sidekiq process restarted mid-run).
      # Fall back to a liveness check since we can no longer reap it.
      begin
        Process.getpgid(pid)
        :running
      rescue Errno::ESRCH
        [ :completed, nil ]
      end
    rescue Errno::ESRCH
      [ :completed, nil ]
    end
  end
end
