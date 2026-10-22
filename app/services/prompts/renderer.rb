module Prompts
  class Renderer
    # Names usable as custom `{NAME}` placeholders (workflow variables).
    VARIABLE_NAME = /\A[A-Za-z][A-Za-z0-9_]*\z/
    TOKEN = /\{([A-Za-z][A-Za-z0-9_]*)\}/
    PREV_OUTPUT_LIMIT = 3000
    # Time zone the {STARTED_ON} date is shown in.
    STARTED_ON_TIME_ZONE = "Australia/Brisbane"

    # Every token the renderer substitutes without custom variables, for UI cheatsheets.
    # Guarded by renderer_spec against `built_ins` drifting from this list.
    BUILT_IN_TOKENS = (
      %w[{JIRA} {PR} {REVIEWER} {SKILLS} {PR_SKILLS} {IMAGES} {TASK} {SLACK}] +
      ProjectPlaceholders::TOKENS +
      %w[{CI_OUTPUT} {CI_STATUS} {STARTED_ON} {STAGE_NAME} {PREV_OUTPUT}]
    ).freeze

    def self.render(template_body, workflow)
      new(template_body, workflow).render
    end

    # Every placeholder available for this workflow, token => current value.
    # Single source for what the renderer substitutes (and what the UI can list).
    def self.placeholders_for(workflow)
      new("", workflow).values
    end

    def initialize(template_body, workflow)
      @template_body = template_body
      @workflow = workflow
    end

    def render
      # One pass over the tokens, so a substituted value is never re-scanned for more tokens.
      template_body.gsub(TOKEN) { values.fetch("{#{$1}}", $&) }
    end

    # Custom variables win over the built-ins of the same name only for names the
    # built-ins don't define, so a variable can't hijack {PR}, {JIRA}, ...
    def values
      @values ||= custom_variables.merge(built_ins)
    end

    private

    attr_reader :template_body, :workflow

    def built_ins
      {
        "{JIRA}" => workflow.jira_ticket.to_s,
        "{PR}" => workflow.github_pr_url.to_s,
        "{REVIEWER}" => Github::Client.parse_reviewers(workflow.github_reviewer).join(","),
        "{SKILLS}" => workflow.skill_list.join(", "),
        "{PR_SKILLS}" => workflow.pr_skill_list.join(", "),
        "{IMAGES}" => workflow.image_paths.join(", "),
        "{TASK}" => workflow.task_description.to_s,
        "{SLACK}" => workflow.slack_url.to_s,
        **ProjectPlaceholders.for(workflow.project),
        "{CI_OUTPUT}" => workflow.ci_output_path.to_s,
        "{CI_STATUS}" => workflow.ci_exit_status.to_s,
        "{STARTED_ON}" => workflow.created_at.in_time_zone(STARTED_ON_TIME_ZONE).strftime("%d/%m/%Y"),
        "{STAGE_NAME}" => workflow.current_stage&.display_name.to_s,
        "{PREV_OUTPUT}" => previous_output
      }
    end

    def custom_variables
      workflow.variables.reject { |_name, value| value.to_s.empty? }.to_h { |name, value| [ "{#{name}}", value.to_s ] }
    end

    # What the previous runbook stage's agent printed, so a stage can build on it.
    def previous_output
      previous = workflow.runbook? ? workflow.previous_runbook_stage : nil
      run = previous&.stage_runs&.find_by(action: "stage_completed")
      run&.output.to_s.last(PREV_OUTPUT_LIMIT)
    end
  end
end
