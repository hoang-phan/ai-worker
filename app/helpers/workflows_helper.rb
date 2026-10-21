module WorkflowsHelper
  WORKFLOW_STATUS_BADGE_CLASSES = {
    "done" => "badge-success",
    "merged" => "badge-success",
    "jira_updated" => "badge-success",
    "uat_tested" => "badge-success",
    "implementing" => "badge-info",
    "reviewing" => "badge-info",
    "waiting" => "badge-info",
    "uat_waiting" => "badge-info",
    "uat_testing" => "badge-info",
    "local_testing" => "badge-info",
    "errored" => "badge-danger"
  }.freeze

  def workflow_status_badge_class(workflow_or_status)
    status = workflow_or_status.respond_to?(:status) ? workflow_or_status.status : workflow_or_status
    WORKFLOW_STATUS_BADGE_CLASSES.fetch(status.to_s, "badge-neutral")
  end

  def workflow_status_badge(workflow)
    content_tag(:span, workflow.status, class: "badge #{workflow_status_badge_class(workflow)}")
  end

  def stage_runnable?(workflow, stage, current_stage = workflow.current_stage)
    workflow.runbook? && workflow.implementing? && !workflow.processing? && current_stage == stage
  end

  def current_stage_badge(workflow, stage, current_stage = workflow.current_stage)
    return unless current_stage == stage

    workflow.waiting? ? "waiting for Next" : "current"
  end
end
