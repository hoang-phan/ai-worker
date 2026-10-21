module Workflows
  # How a workflow is named in the UI: the short label, the one-line brief for compact listings, and the show-page
  # heading. Reads the workflow's attributes only; nothing is persisted.
  class Label
    VARIABLES_LENGTH = 60
    PR_URL = %r{github\.com/([^/]+/[^/]+)/pull/(\d+)}

    def initialize(workflow)
      @workflow = workflow
    end

    # "org/repo#123" for PR-review workflows, otherwise the Jira ticket / task. Nil for a PR review whose URL
    # doesn't parse, so callers see exactly what Workflow#label always returned.
    def value
      if @workflow.runbook?
        runbook_label
      elsif @workflow.pr_review?
        @workflow.github_pr_url.to_s[PR_URL] && "#{$1}##{$2}"
      elsif @workflow.project.personal?
        @workflow.task_description.to_s
      else
        @workflow.jira_ticket.to_s
      end
    end

    def to_s
      value.to_s
    end

    def brief
      (@workflow.summary.presence || value).to_s.squish.truncate(Workflow::SUMMARY_LENGTH)
    end

    def heading
      if @workflow.runbook?
        value
      elsif @workflow.pr_review?
        "Review #{value}"
      elsif @workflow.project.personal?
        "Task ##{@workflow.id}"
      else
        @workflow.jira_ticket
      end
    end

    private

    def runbook_label
      summary = @workflow.variables.values.compact_blank.join(" · ").squish.truncate(VARIABLES_LENGTH)
      summary.presence || "Run ##{@workflow.id}"
    end
  end
end
