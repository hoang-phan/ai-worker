module Workflows
  # The stage a workflow is on right now: a runbook's stage at current_stage_id; for the others the pipeline stage at
  # current_stage_id while the workflow is in the status that stage maps to (Workflows::StageFlow), otherwise the stage
  # type the status maps to (Workflows::StageResolver: workflows that predate current_stage_id, the post-merge Jira
  # update and UAT test, or a status set by hand). Nil when the status has no stage. Lazy types are created on first use.
  class CurrentStage
    def initialize(workflow)
      @workflow = workflow
    end

    def call
      return workflow.stages.find_by(id: workflow.current_stage_id) if workflow.runbook?

      stored_stage || resolved_stage
    end

    private

    attr_reader :workflow

    # A stored stage is only trusted while the status still labels it; anything else moved the workflow by status alone.
    def stored_stage
      return nil unless workflow.current_stage_id

      stage = workflow.stages.find_by(id: workflow.current_stage_id)
      return nil unless stage && Workflows::StageFlow.pipeline_type?(stage.stage_type)

      stage if Workflows::StageFlow.new(workflow).status_for(stage).to_s == workflow.status
    end

    def resolved_stage
      stage_type = Workflows::StageResolver.stage_type_for(
        status: workflow.status, kind: workflow.kind, personal: workflow.project.personal?,
        ci_loop: workflow.development? && workflow.project.ci_loop_ready?
      )
      return nil unless stage_type

      # The Jira-update and UAT-test stages aren't seeded with the workflow (older workflows
      # predate it), so create it the first time it's needed.
      return workflow.stages.find_or_create_by!(stage_type: stage_type) if Workflows::StageResolver::LAZY_STAGE_TYPES.include?(stage_type)

      workflow.stages.find_by(stage_type: stage_type)
    end
  end
end
