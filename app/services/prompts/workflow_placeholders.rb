module Prompts
  # The workflow-derived prompt tokens, token => value. Project tokens live in ProjectPlaceholders.
  class WorkflowPlaceholders
    TOKENS = %w[
      {JIRA} {PR} {REVIEWER} {SKILLS} {PR_SKILLS} {IMAGES} {TASK} {SLACK}
      {CI_OUTPUT} {CI_STATUS} {STARTED_ON} {STAGE_NAME} {PREV_OUTPUT}
    ].freeze
    PREV_OUTPUT_LIMIT = 3000
    # Time zone the {STARTED_ON} date is shown in.
    STARTED_ON_TIME_ZONE = "Australia/Brisbane"

    def self.for(workflow)
      new(workflow).to_h
    end

    def initialize(workflow)
      @workflow = workflow
    end

    def to_h
      {
        "{JIRA}" => workflow.jira_ticket.to_s,
        "{PR}" => workflow.github_pr_url.to_s,
        "{REVIEWER}" => Github::Client.parse_reviewers(workflow.github_reviewer).join(","),
        "{SKILLS}" => workflow.skill_list.join(", "),
        "{PR_SKILLS}" => workflow.pr_skill_list.join(", "),
        "{IMAGES}" => workflow.image_paths.join(", "),
        "{TASK}" => workflow.task_description.to_s,
        "{SLACK}" => workflow.slack_url.to_s,
        "{CI_OUTPUT}" => workflow.ci_output_path.to_s,
        "{CI_STATUS}" => workflow.ci_exit_status.to_s,
        "{STARTED_ON}" => workflow.created_at.in_time_zone(STARTED_ON_TIME_ZONE).strftime("%d/%m/%Y"),
        "{STAGE_NAME}" => workflow.current_stage&.display_name.to_s,
        "{PREV_OUTPUT}" => previous_output
      }
    end

    private

    attr_reader :workflow

    # What the previous runbook stage's agent printed, so a stage can build on it.
    def previous_output
      previous = workflow.runbook? ? workflow.previous_runbook_stage : nil
      run = previous&.stage_runs&.find_by(action: "stage_completed")
      run&.output.to_s.last(PREV_OUTPUT_LIMIT)
    end
  end
end
