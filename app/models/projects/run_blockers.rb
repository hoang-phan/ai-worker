module Projects
  # The project readiness checks shared by the agent-run services (Bugsnag::TriageSync,
  # Jira::TicketSync, Slack::ReviewSync, Brainstorm::Planner). Each check returns its
  # message when the project is not ready, nil otherwise; `messages` collects them.
  class RunBlockers
    def initialize(project)
      @project = project
    end

    # Messages for the named checks, in the order asked, skipping the ones that pass.
    def messages(*checks)
      checks.filter_map { |check| public_send(check) }
    end

    def jira_kind
      "project kind is not jira" unless project.jira?
    end

    def personal_kind
      "project kind is not personal" unless project.personal?
    end

    def jira_site_url
      "Jira site URL is not set" if project.jira_base_url.blank?
    end

    def assignee
      "assignee is not set" if project.jira_assignee.blank?
    end

    def default_reviewers
      "default GitHub reviewers are not set (workflows require a reviewer)" if project.default_reviewers.blank?
    end

    def repo
      "GitHub repo is not set" if project.repo_full_name.blank?
    end

    def slack_mention
      "Slack mention is not set" if project.slack_mention.blank?
    end

    def local_directory
      "local directory does not exist" unless Dir.exist?(project.local_directory.to_s)
    end

    def brainstorm_goal
      "no goal set" if project.brainstorm_goal.blank?
    end

    private

    attr_reader :project
  end
end
