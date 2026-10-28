module StagesHelper
  def stage_run_mode_options
    Stage.run_modes.keys.map do |run_mode|
      [ run_mode == "agent" ? "Run the prompt with the agent" : "Post the text to Slack", run_mode ]
    end
  end

  def stage_template_options(stage)
    stage.candidate_templates.map { |template| [ template.name, template.id, { data: { body: template.body } } ] }
  end

  def stage_runnable?(workflow, stage, current_stage = workflow.current_stage)
    workflow.can_run_stage? && current_stage == stage
  end

  def current_stage_badge(workflow, stage, current_stage = workflow.current_stage)
    return unless current_stage == stage

    workflow.waiting? ? "waiting for Next" : "current"
  end

  # [name column, detail column] headers of the workflow page's stage table.
  def stage_table_headers(workflow)
    workflow.runbook? ? [ "Stage", "Channel" ] : [ "Type", "Template" ]
  end

  def stage_row_name(workflow, stage)
    workflow.runbook? ? stage.display_name : stage.stage_type
  end

  # run_mode / "waits for ..." / advance-mode badges beside a stage row's name; only "waits for" shows outside runbooks.
  def stage_row_badges(workflow, stage)
    runbook = workflow.runbook?
    safe_join([
      (badge(stage.run_mode) if runbook),
      (badge("waits for #{stage.wait_for_workflow}") if stage.wait_for_workflow.present?),
      (badge(stage.auto_advance? ? "→ auto" : "⏸ then Next") if runbook)
    ].compact, " ")
  end

  # Slack channel for a runbook stage, prompt template name otherwise.
  def stage_row_detail(workflow, stage)
    workflow.runbook? ? stage.channel : stage.effective_template&.name
  end
end
