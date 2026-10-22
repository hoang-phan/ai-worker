module Workflows
  # The stage a workflow is on right now: a runbook's stage at current_stage_id, otherwise the stage type its status
  # maps to (see Workflows::StageResolver). Nil when the status has no stage. Lazy types are created on first use.
  class CurrentStage
    def initialize(workflow)
      @workflow = workflow
    end

    def call
      return workflow.stages.find_by(id: workflow.current_stage_id) if workflow.runbook?

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

    private

    attr_reader :workflow
  end
end
