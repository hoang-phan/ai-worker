module Slack
  # One ping run dir: tmp/slack_pings/<workflow_id>/<started_at>/{pid,agent.log}. ReviewNotifier creates it,
  # PingCollector reads it back.
  class PingRun
    ROOT = Rails.root.join("tmp", "slack_pings")
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

    def stale?(now = Time.current)
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
