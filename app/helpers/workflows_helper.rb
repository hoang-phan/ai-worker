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

  # "synced 5 minutes ago", or nil when hours have never been synced from Jira.
  def jira_synced_phrase(workflow)
    "synced #{time_ago_in_words(workflow.jira_logged_synced_at)} ago" if workflow.jira_logged_synced_at
  end

  # "review" / "runbook" badges shown beside a workflow's label.
  def workflow_kind_badges(workflow)
    safe_join([
      (content_tag(:span, "review", class: "badge badge-neutral") if workflow.pr_review?),
      (content_tag(:span, "runbook", class: "badge badge-neutral") if workflow.runbook?)
    ].compact)
  end

  # Logged-hours badge for development workflows; nil for other kinds.
  def workflow_logged_time_badge(workflow, seconds)
    return unless workflow.development?

    if seconds.to_i.positive?
      title = [ "Hours you have logged in Jira", jira_synced_phrase(workflow) ].compact.join(", ")
      content_tag(:span, "#{logged_hours(seconds)} h", class: "badge badge-success", title: title)
    else
      content_tag(:span, "Not logged", class: "badge badge-neutral")
    end
  end

  # Only rows with nothing logged yet are targets of the header select-all checkbox.
  def time_log_checkbox_data(seconds)
    seconds.to_i.positive? ? {} : { select_all_target: "row" }
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
