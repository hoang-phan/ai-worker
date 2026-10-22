require "fileutils"

module Brainstorm
  # Owns the on-disk lifecycle of a brainstorm agent run. Planner supplies the
  # project-specific launch inputs; this class keeps the detached-run state and
  # retries one aborted API stream before reporting its terminal reason.
  class RunLifecycle
    def initialize(dir:, stale_after:, error_class: FetchError, run: nil, runner: AiCli::Runner)
      @dir = Pathname(dir)
      @stale_after = stale_after
      @error_class = error_class
      @run = run
      @runner = runner
    end

    def running?
      run.running?
    end

    def last_started_at
      run.last_started_at
    end

    def start(prepare: nil, **launch_inputs)
      return false if running?

      FileUtils.mkdir_p(dir)
      FileUtils.rm_f(retried_file)
      log_file.write("")
      prepare&.call
      launch(**launch_inputs)
      true
    end

    # nil while running (or nothing started); once finished, yields the rows
    # from result.json. Raises the supplied error class on terminal failure.
    def poll(prepare: nil, **launch_inputs, &block)
      return unless pid_file.exist?

      unless running? || result_file.exist?
        FileUtils.rm_f(pid_file)
        return retry_missing_result(prepare: prepare, **launch_inputs)
      end

      run.poll(&block)
    end

    private

    attr_reader :dir, :stale_after, :error_class, :runner

    def run
      @run ||= AiCli::DetachedRun.new(
        dir: dir, result_name: "result.json", stale_after: stale_after, error_class: error_class,
        runner: runner
      )
    end

    def launch(**launch_inputs)
      run.start(**launch_inputs)
    end

    def retry_missing_result(prepare:, **launch_inputs)
      outcome = RunOutcome.new(log_path: log_file, retried: retried_file.exist?)
      unless outcome.retry?
        raise error_class, "agent wrote no #{result_file.basename} (#{outcome.failure_reason}); see #{log_file}"
      end

      FileUtils.touch(retried_file)
      prepare&.call
      launch(**launch_inputs)
      nil
    end

    def pid_file = dir.join("pid")
    def result_file = dir.join("result.json")
    def retried_file = dir.join("retried")
    def log_file = run.log_path
  end
end
