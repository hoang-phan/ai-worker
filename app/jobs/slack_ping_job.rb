# Runs every 5 minutes. Has Slack::PingCollector read back the permalinks of finished Slack review pings (posted by
# detached agent runs) into the workflows' review threads and drop ping dirs of deleted workflows. Never waits on a run.
class SlackPingJob < ApplicationJob
  queue_as :default

  def perform(collector: Slack::PingCollector.new)
    collector.collect_all
  end
end
