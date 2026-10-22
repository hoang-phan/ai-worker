require "fileutils"
require "json"

module AiCli
  # State machine shared by the services that run the agent CLI detached and
  # read a JSON array back from a result file (Jira::AgentFetcher,
  # Slack::MentionFetcher, Bugsnag::Triager).
  #
  # `runner` is anything responding to start(cwd, prompt, log_path:,
  # allowed_tools:, **opts) and poll(pid); specs pass a fake.
  #
  # State lives in `dir`: pid, started_at, agent.log and <result_name>.
  class DetachedRun
    def initialize(dir:, result_name:, stale_after:, error_class:, runner: AiCli::Runner)
      @dir = Pathname(dir)
      @result_name = result_name
      @stale_after = stale_after
      @error_class = error_class
      @runner = runner
    end

    # True only while the agent process is actually alive. A leftover pid
    # file from a finished or killed process doesn't count; `poll` still
    # picks it up to read the result.
    def running?
      pid_file.exist? && runner.poll(pid_file.read.to_i) == :running
    end

    def last_started_at
      started_file.exist? ? Time.zone.at(started_file.read.to_f) : nil
    end

    # No-op (returns false) if the process is still alive. A stale pid file
    # from a dead process is overwritten (any unread result is discarded).
    def start(cwd:, prompt:, allowed_tools: nil, model: nil, effort: nil)
      return false if running?

      FileUtils.mkdir_p(dir)
      FileUtils.rm_f(result_file)
      options = { model: model, effort: effort }.compact
      pid = runner.start(cwd.to_s, prompt, log_path: log_file.to_s, allowed_tools: allowed_tools, **options)
      pid_file.write(pid)
      started_file.write(Time.current.to_f)
      true
    end

    # nil while still running (or nothing started). Once finished, the parsed
    # rows (passed through the block, if given). Raises error_class on failure.
    def poll
      return unless pid_file.exist?

      if runner.poll(pid_file.read.to_i) == :running
        return unless stale?

        clear
        raise error_class, "agent did not finish within #{stale_after.inspect}"
      end

      clear
      rows = read_rows
      block_given? ? yield(rows) : rows
    end

    def log_path = log_file
    def result_path = result_file

    def read_rows
      raise error_class, "agent wrote no #{result_file.basename}; see #{log_file}" unless result_file.exist?

      data = JSON.parse(result_file.read)
      raise error_class, "#{result_file.basename} is not a JSON array" unless data.is_a?(Array)

      data
    rescue JSON::ParserError => e
      raise error_class, "invalid JSON in #{result_file.basename}: #{e.message}"
    end

    private

    attr_reader :dir, :result_name, :stale_after, :error_class, :runner

    def stale?
      last_started_at.nil? || last_started_at < stale_after.ago
    end

    def clear
      FileUtils.rm_f(pid_file)
    end

    def pid_file = dir.join("pid")
    def started_file = dir.join("started_at")
    def result_file = dir.join(result_name)
    def log_file = dir.join("agent.log")
  end
end
