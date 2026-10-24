module WorkflowPagesHelper
  # Detail partial selected using the same precedence as the workflow details card.
  def workflow_details_partial(workflow, project)
    return "workflows/details/pr_review" if workflow.pr_review?
    return "workflows/details/runbook" if workflow.runbook?

    project.personal? ? "workflows/details/task" : "workflows/details/jira"
  end

  # Label of the runbook Next button: the following stage, or "Finish" after the last one.
  def workflow_advance_label(workflow)
    next_stage = workflow.next_runbook_stage
    next_stage ? "Next: #{next_stage.display_name}" : "Finish"
  end

  # [[label, id], ...] for the new-runbook "Start with the stages of" select, newest runbook first.
  def runbook_copy_source_options(project)
    project.workflows.runbook.order(id: :desc).map { |source| [ "##{source.id} #{source.label} (#{source.status})", source.id ] }
  end
end
