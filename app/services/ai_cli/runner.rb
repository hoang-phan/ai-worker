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
    # To support another CLI (e.g. codex), add an entry here.
    AGENTS = {
      "claude" => { binary: "claude", args: [ "-p", :prompt, "--dangerously-skip-permissions" ] },
      "cursor" => { binary: "agent", args: [ "-p", :prompt, "--force" ] }
    }.freeze

    # The server-wide agent, chosen at boot via the AGENT env var, e.g.
    # `AGENT=cursor bin/dev`. Defaults to claude.
    def self.agent
      ENV["AGENT"].presence || "claude"
    end

    def self.start(project_directory, prompt, log_path:)
      new(log_tag: nil).start(project_directory, prompt, log_path: log_path)
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

    def start(project_directory, prompt, log_path:)
      FileUtils.mkdir_p(File.dirname(log_path))

      Process.spawn(
        *command(self.class.agent, prompt),
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
    def command(agent, prompt)
      spec = AGENTS[agent] or raise CommandError, "unknown AGENT #{agent.inspect} (expected one of #{AGENTS.keys.join(", ")})"
      command = [ spec[:binary], *spec[:args].map { |arg| arg == :prompt ? prompt : arg } ]
      if agent == "claude" && ENV["AI_VERBOSE"].present?
        command += [ "--output-format", "stream-json", "--verbose", "--include-partial-messages" ]
      end
      command
    end

    def log_line(line)
      Rails.logger.info("[ai_cli #{log_tag}] #{line.chomp}")
    end
  end
end
