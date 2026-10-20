module AiCli
  # Naming convention for the per-workflow agent logs: log/ai_runs/workflow-<id>-<unix>.log.
  module RunLogs
    DIR = Rails.root.join("log", "ai_runs")

    def self.new_path(workflow_id, at: Time.current, dir: DIR)
      File.join(dir, "workflow-#{workflow_id}-#{at.to_i}.log")
    end

    # Newest existing log for the workflow (by mtime), or nil. The "-" after the id keeps workflow 1 apart from 12.
    def self.latest(workflow_id, dir: DIR)
      Dir[File.join(dir, "workflow-#{workflow_id}-*.log")].max_by { |path| File.mtime(path) }
    end
  end
end
