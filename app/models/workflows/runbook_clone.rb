module Workflows
  # The runbook's Clone button: a fresh pending runbook with the same stages and the variables the user
  # set up front (channel etc.). Variables a stage emitted (version, work list, tag …) are dropped so
  # last run's results can't leak into this one.
  class RunbookClone
    Result = Struct.new(:status, :copy, :error, keyword_init: true)

    def initialize(workflow)
      @workflow = workflow
    end

    def call
      return Result.new(status: :not_runbook) unless workflow.runbook?

      project = workflow.project
      copy = project.workflows.new(kind: :runbook, position: project.next_workflow_position, copy_stages_from_id: workflow.id,
                                   variables: workflow.input_variables)
      if copy.save
        Result.new(status: :created, copy: copy)
      else
        Result.new(status: :invalid, copy: copy, error: copy.errors.full_messages.to_sentence)
      end
    end

    private

    attr_reader :workflow
  end
end
