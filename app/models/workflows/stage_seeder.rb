module Workflows
  # Creates a new workflow's initial stages, by kind and project kind. Runbooks start as copies of another runbook's stages.
  class StageSeeder
    # Runbook stage columns carried over when a runbook is created from another one.
    COPIED_RUNBOOK_ATTRIBUTES = %w[name position run_mode channel prompt auto_advance wait_for_workflow].freeze

    def initialize(workflow)
      @workflow = workflow
    end

    def call
      if workflow.runbook?
        copy_runbook_stages
      elsif workflow.pr_review?
        workflow.stages.create!(stage_type: :pr_review)
      elsif workflow.project.personal?
        workflow.stages.create!(stage_type: :task)
      elsif workflow.project.ci_loop_ready?
        %i[simple_implementation ci_check ci_verify pr_create pr_check].each { |stage_type| workflow.stages.create!(stage_type: stage_type) }
      else
        workflow.stages.create!(stage_type: :implementation)
        workflow.stages.create!(stage_type: :pr_check)
      end
    end

    private

    attr_reader :workflow

    def copy_runbook_stages
      workflow.copy_source&.stages&.each do |source|
        workflow.stages.create!(source.slice(*COPIED_RUNBOOK_ATTRIBUTES).merge(stage_type: :runbook_step))
      end
    end
  end
end
