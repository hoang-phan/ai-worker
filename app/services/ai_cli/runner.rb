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

    def self.start(...) = new.start(...)

    # Non-blocking: returns :running, or [:completed, Process::Status-or-nil].
    def self.poll(pid)
      new.poll(pid)
    end

    # Seams for specs, defaulting to the real collaborators: spawn is called like Process.spawn; command_builder
    # responds to `new(agent:, prompt:, **options)` returning an object with #to_a (Command); providers responds to
    # `fetch(name)` returning a provider with #wrap (Providers).
    def initialize(spawn: Process.method(:spawn), command_builder: Command, providers: Providers)
      @spawn = spawn
      @command_builder = command_builder
      @providers = providers
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
    # provider: name of the agent CLI for this run (see Providers); the app-wide agent setting when nil.
    #
    # model / effort: select the model and reasoning level for this run instead of the CLI's defaults, e.g. a stronger
    # model for brainstorming. Claude receives `--model` / `--effort`; Codex receives `--model` and
    # `-c model_reasoning_effort=...`. Cursor ignores them.
    def start(project_directory, prompt, log_path:, allowed_tools: nil, mcp_config: nil, env: {}, disallowed_tools: [], model: nil, effort: nil, provider: nil)
      FileUtils.mkdir_p(File.dirname(log_path))

      command_options = { allowed_tools: allowed_tools, mcp_config: mcp_config, disallowed_tools: disallowed_tools,
                          model: model, effort: effort }
      command = agent_command(project_directory, prompt, provider: provider, **command_options)

      @spawn.call(
        spawn_env(env),
        *command,
        chdir: project_directory,
        in: File::NULL,
        out: [ log_path, "a" ],
        err: [ log_path, "a" ]
      )
    end

    def poll(pid)
      ProcessStatus.new.call(pid)
    end

    private

    # Final argv for the run's provider (the app-wide agent unless `provider` names one), set up by the provider
    # (cursor writes its MCP file around the run).
    def agent_command(project_directory, prompt, provider: nil, **command_options)
      agent = provider.presence || self.class.agent
      command = @command_builder.new(agent: agent, prompt: prompt, **command_options).to_a
      @providers.fetch(agent).wrap(command, project_directory: project_directory, mcp_config: command_options[:mcp_config])
    end

    # Process environment for the spawn: LEAKED_ENV unset (nil), the caller's env stringified on top (so it wins).
    def spawn_env(env)
      # `claude -p` stops background subagents 10 minutes after the last
      # turn; 0 makes it wait for them. STALE_AFTER is the real timeout.
      LEAKED_ENV.index_with(nil).merge("CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS" => "0").merge(env.transform_values(&:to_s))
    end
  end
end
