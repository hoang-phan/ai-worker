require "json"
require "open3"
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
    # Non-interactive invocation per agent. stdin is /dev/null, so every
    # agent must be told to skip permission prompts or it would hang.
    # To support another CLI, add an entry here.
    AGENTS = {
      "claude" => { binary: "claude", args: [ "-p", :prompt, "--dangerously-skip-permissions" ] },
      "cursor" => { binary: "agent", args: [ "-p", :prompt, "--force" ] },
      "codex" => { binary: "codex", args: [ "exec", "--dangerously-bypass-approvals-and-sandbox", :prompt ] }
    }.freeze

    AGENT_CACHE_KEY = "ai_cli/agent".freeze

    # The app-wide agent, resolved on every call so a change takes effect on
    # the next run without a restart. Stored in Rails.cache (shared by the web
    # and Sidekiq processes, so it needs a cross-process store such as
    # file_store); falls back to the AGENT env var, then claude.
    def self.agent
      cached = Rails.cache.read(AGENT_CACHE_KEY)
      return cached if AGENTS.key?(cached)

      ENV["AGENT"].presence || "claude"
    end

    def self.agent=(name)
      name = name.to_s
      raise ArgumentError, "unknown agent #{name.inspect} (expected one of #{AGENTS.keys.join(", ")})" unless AGENTS.key?(name)

      Rails.cache.write(AGENT_CACHE_KEY, name)
    end

    def self.available_agents
      AGENTS.keys
    end

    def self.start(project_directory, prompt, log_path:, allowed_tools: nil, mcp_config: nil, env: {}, disallowed_tools: [])
      new(log_tag: nil).start(project_directory, prompt, log_path: log_path, allowed_tools: allowed_tools,
                              mcp_config: mcp_config, env: env, disallowed_tools: disallowed_tools)
    end

    # Non-blocking: returns :running, or [:completed, Process::Status-or-nil].
    def self.poll(pid)
      new(log_tag: nil).poll(pid)
    end

    # Logs (and returns) any log file content written since from_offset.
    # Returns the new offset to pass in next time.
    def self.tail_new_lines(log_path, from_offset:, log_tag: nil)
      new(log_tag: log_tag).tail_new_lines(log_path, from_offset: from_offset)
    end

    def initialize(log_tag:)
      @log_tag = log_tag
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
    def start(project_directory, prompt, log_path:, allowed_tools: nil, mcp_config: nil, env: {}, disallowed_tools: [])
      FileUtils.mkdir_p(File.dirname(log_path))

      # `claude -p` stops background subagents 10 minutes after the last
      # turn; 0 makes it wait for them. STALE_AFTER is the real timeout.
      agent = self.class.agent
      cmd = command(agent, prompt, allowed_tools, mcp_config, disallowed_tools)
      cmd = with_cursor_mcp_file(project_directory, mcp_config, cmd) if agent == "cursor" && mcp_config.present?

      Process.spawn(
        { "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS" => "0" }.merge(env.transform_values(&:to_s)),
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

    def tail_new_lines(log_path, from_offset:)
      return [ "", from_offset ] unless File.exist?(log_path)

      content = File.open(log_path, "rb") do |f|
        f.seek(from_offset)
        f.read
      end.to_s

      content.each_line { |line| log_line(line) }
      [ content, from_offset + content.bytesize ]
    end

    private

    attr_reader :log_tag

    # AI_VERBOSE=1 switches the claude log from a single end-of-run blob to
    # incremental stream-json events (text_delta/tool_use/etc.) written as
    # the run progresses — set it before boot, e.g. `AI_VERBOSE=1 bin/dev`.
    # Only applies to claude.
    def command(agent, prompt, allowed_tools = nil, mcp_config = nil, disallowed_tools = [])
      spec = AGENTS[agent] or raise CommandError, "unknown AGENT #{agent.inspect} (expected one of #{AGENTS.keys.join(", ")})"
      args = spec[:args].map { |arg| arg == :prompt ? prompt : arg }
      if agent == "claude" && allowed_tools.present?
        args = args.map { |arg| arg == "--dangerously-skip-permissions" ? [ "--allowedTools", *allowed_tools ] : arg }.flatten
      end
      command = [ binary_for(agent, spec), *args ]
      command += [ "--mcp-config", mcp_config.to_s ] if agent == "claude" && mcp_config.present?
      command.insert(2, *codex_mcp_overrides(mcp_config)) if agent == "codex" && mcp_config.present? # before the prompt
      command << "--approve-mcps" if agent == "cursor" && mcp_config.present? && cursor_supports?("--approve-mcps")
      command += [ "--disallowedTools", *disallowed_tools ] if agent == "claude" && disallowed_tools.present?
      if agent == "claude" && ENV["AI_VERBOSE"].present?
        command += [ "--output-format", "stream-json", "--verbose", "--include-partial-messages" ]
      end
      command
    end

    # Cursor's CLI is installed as `agent` by newer versions and `cursor-agent` by older ones.
    def binary_for(agent, spec)
      return spec[:binary] unless agent == "cursor"

      [ spec[:binary], "cursor-agent" ].find { |name| executable_on_path?(name) } || spec[:binary]
    end

    def executable_on_path?(name)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) && !File.directory?(File.join(dir, name)) }
    end

    def cursor_supports?(flag)
      out, _status = Open3.capture2e(binary_for("cursor", AGENTS["cursor"]), "--help")
      out.include?(flag)
    rescue SystemCallError
      false
    end

    # codex has no per-run MCP config file; each server is set field by field with TOML values (JSON strings and
    # arrays of strings are valid TOML).
    def codex_mcp_overrides(mcp_config)
      mcp_servers(mcp_config).flat_map do |name, server|
        overrides = { "command" => server["command"].to_json, "startup_timeout_sec" => 90 }
        overrides["args"] = Array(server["args"]).to_json if server["args"]
        overrides["env"] = "{" + server["env"].map { |k, v| "#{k.to_json} = #{v.to_json}" }.join(", ") + "}" if server["env"].present?
        overrides.flat_map { |key, value| [ "-c", "mcp_servers.#{name}.#{key}=#{value}" ] }
      end
    end

    def mcp_servers(mcp_config)
      JSON.parse(File.read(mcp_config)).fetch("mcpServers", {})
    end

    # cursor reads project MCP servers from <cwd>/.cursor/mcp.json. Write the run's servers there (keeping any
    # existing file aside), keep it out of git, and have a tiny shell wrapper put things back when the run ends.
    def with_cursor_mcp_file(project_directory, mcp_config, cmd)
      dir = File.join(project_directory, ".cursor")
      file = File.join(dir, "mcp.json")
      backup = "#{file}.ai-worker-bak"
      FileUtils.mkdir_p(dir)
      FileUtils.mv(file, backup) if File.exist?(file) && !File.exist?(backup)
      File.write(file, JSON.pretty_generate(mcpServers: mcp_servers(mcp_config)))
      exclude_from_git(project_directory)

      [ "sh", "-c", 'trap \'rm -f "$0"; [ -f "$0.ai-worker-bak" ] && mv "$0.ai-worker-bak" "$0"\' EXIT; "$@"', file, *cmd ]
    end

    def exclude_from_git(project_directory)
      exclude = File.join(project_directory, ".git", "info", "exclude")
      return unless File.directory?(File.dirname(exclude))

      current = File.exist?(exclude) ? File.read(exclude) : ""
      return if current.include?(".cursor/mcp.json")

      File.write(exclude, current + (current.end_with?("\n") || current.empty? ? "" : "\n") + ".cursor/mcp.json\n.cursor/mcp.json.ai-worker-bak\n")
    end

    def log_line(line)
      Rails.logger.info("[ai_cli #{log_tag}] #{line.chomp}")
    end
  end
end
