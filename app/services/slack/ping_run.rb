require "fileutils"

module Slack
  # One ping run dir: tmp/slack_pings/<workflow_id>/<started_at>/{pid,agent.log}. Owns both halves of that
  # layout: `start!` (ReviewNotifier) creates it, `running?` / `permalink` (PingCollector) read it back.
  class PingRun
    ROOT = AgentRuns::StateRoot.join("slack_pings")
    STALE_AFTER = 5.minutes

    # The dir for a ping of `workflow_id` started at `started_at` (not created).
    def self.for(root, workflow_id, started_at)
      new(Pathname(root).join(workflow_id.to_s, started_at.to_i.to_s))
    end

    attr_reader :dir

    def initialize(dir)
      @dir = Pathname(dir)
    end

    def pid_file
      dir.join("pid")
    end

    def log_file
      dir.join("agent.log")
    end

    def started_at
      Time.zone.at(dir.basename.to_s.to_i)
    end

    # Creates the dir, starts the detached run in it (logging to agent.log) and records its pid.
    def start!(runner, prompt, **run_options)
      FileUtils.mkdir_p(dir)
      pid = runner.start(to_s, prompt, log_path: log_file.to_s, **run_options)
      pid_file.write(pid)
    end

    # Alive and fresh. A missing pid file counts as finished, as does a stale run.
    def running?(poller, now)
      pid_file.exist? && poller.call(pid_file.read.to_i) == :running && !stale?(now)
    end

    def stale?(now)
      started_at <= now - STALE_AFTER
    end

    # The first Slack permalink in the agent log, or nil.
    def permalink
      log_file.exist? ? log_file.read[ThreadRef::PERMALINK] : nil
    end

    def to_s
      dir.to_s
    end
  end
end
