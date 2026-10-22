require "fileutils"

module Slack
  # Reads back the posting runs started by Slack::ReviewNotifier: walks tmp/slack_pings/<workflow_id>/<started_at>/,
  # and the first permalink found in a finished run's agent.log becomes Workflow#slack_review_thread_ts when blank.
  class PingCollector
    def initialize(root: PingRun::ROOT, poller: AiCli::Runner.method(:poll))
      @root = Pathname(root)
      @poller = poller
    end

    def pending_workflow_ids
      Dir.glob(root.join("*")).map { |path| File.basename(path).to_i }
    end

    # Collects every workflow with a ping dir; dirs of workflows that no longer exist are removed.
    def collect_all(find_workflow: ->(id) { Workflow.find_by(id: id) })
      pending_workflow_ids.each do |id|
        workflow = find_workflow.call(id)
        workflow ? collect(workflow) : FileUtils.rm_rf(root.join(id.to_s))
      end
    end

    # Returns true while a ping of `workflow` is still running.
    def collect(workflow)
      workflow_dir = root.join(workflow.id.to_s)
      outcomes = Dir.glob(workflow_dir.join("*")).sort.map { |path| collect_run(workflow, Pathname(path)) }
      running = outcomes.include?(:running)
      remove_if_empty(workflow_dir) unless running
      running
    rescue Errno::ENOENT
      false
    end

    private

    attr_reader :root, :poller

    # Returns :running while the run is fresh and alive; otherwise reads its permalink and returns :finished.
    # A finished run with a permalink is removed; one without is logged and kept.
    def collect_run(workflow, dir)
      run = PingRun.new(dir)
      return :running if running?(run)

      link = run.permalink
      if link.blank?
        Rails.logger.warn("[Slack::ReviewNotifier] workflow=#{workflow.id} ping gave no permalink; see #{dir}")
      else
        workflow.update!(slack_review_thread_ts: link) if workflow.slack_review_thread_ts.blank?
        FileUtils.rm_rf(dir)
      end
      :finished
    end

    # Fresh and still alive; stale runs count as finished.
    def running?(run)
      state = run.pid_file.exist? ? poller.call(run.pid_file.read.to_i) : [ :completed, nil ]
      state == :running && !run.stale?
    end

    def remove_if_empty(workflow_dir)
      FileUtils.rmdir(workflow_dir) if Dir.empty?(workflow_dir)
    end
  end
end
