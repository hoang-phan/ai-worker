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
    "ci_checking" => "badge-info",
    "ci_verifying" => "badge-info",
    "opening_pr" => "badge-info",
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

  # Seconds logged in Jira as hours, e.g. 5400 => "1.5", 3600 => "1".
  def logged_hours(seconds)
    number_with_precision(seconds.to_i / 3600.0, precision: 2, strip_insignificant_zeros: true)
  end

  def current_stage_badge(workflow, stage, current_stage = workflow.current_stage)
    return unless current_stage == stage

    workflow.waiting? ? "waiting for Next" : "current"
  end

  # [[label, id], ...] for the new-runbook "Start with the stages of" select, newest runbook first.
  def runbook_copy_source_options(project)
    project.workflows.runbook.order(id: :desc).map { |source| [ "##{source.id} #{source.label} (#{source.status})", source.id ] }
  end
end
