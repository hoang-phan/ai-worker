# Runs every minute. Reads back the permalinks of finished Slack review pings (posted by detached agent runs) and
# saves them as the workflows' review threads. Never waits on a run.
class SlackPingJob < ApplicationJob
  queue_as :default

  def perform
    Slack::ReviewNotifier.pending_workflow_ids.each do |id|
      workflow = Workflow.find_by(id: id)
      next FileUtils.rm_rf(Slack::ReviewNotifier::ROOT.join(id.to_s)) unless workflow

      Slack::ReviewNotifier.new(workflow.project).collect(workflow)
    end
  end
end
