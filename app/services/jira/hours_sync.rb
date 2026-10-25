module Jira
  # Mirrors the JIRA_EMAIL user's Jira worklogs into time_logs, so the day allocation, the badges and every hours figure
  # agree with Jira. Discovers sites/workflows and recent ticket keys, reuses one client per site, and aggregates
  # WorklogSiteSync results. A failed ticket keeps its previous rows and is reported in the result. Missing credentials
  # abort the run.
  class HoursSync
    Result = Struct.new(:synced, :failed, keyword_init: true)

    def initialize(client_factory: ->(base_url) { WorklogClient.new(base_url) }, today: -> { Time.zone.today })
      @client_factory = client_factory
      @today = today
    end

    # Every ticket of the app's development workflows, plus the tickets logged this month (even ones the app doesn't know).
    def call
      each_site { |base_url, workflows| sync_site(base_url, workflows, workflows.filter_map(&:jira_key) | recent_keys(base_url)) }
    end

    # Only this month's worklogs: what the day allocation needs, cheap enough to run before every logging.
    def recent(base_url)
      sync_site(base_url, [], recent_keys(base_url))
    end

    private

    def each_site
      result = Result.new(synced: 0, failed: [])
      workflows_by_site.each do |base_url, workflows|
        site = yield(base_url, workflows)
        result.synced += site.synced
        result.failed += site.failed
      end
      result
    end

    def workflows_by_site
      Project.with_jira_site.includes(:workflows).group_by(&:jira_base_url)
             .transform_values { |projects| projects.flat_map { |project| project.workflows.select(&:development?) } }
    end

    def recent_keys(base_url)
      client(base_url).keys_with_my_worklogs_since(@today.call.beginning_of_month - 1.day)
    end

    def sync_site(base_url, workflows, keys)
      WorklogSiteSync.new(client: client(base_url)).call(workflows, keys)
    end

    def client(base_url)
      (@clients ||= {})[base_url] ||= @client_factory.call(base_url)
    end
  end
end
