module Workflows
  # The variables API a workflow exposes to forms and runbook cloning.
  class VariableSet
    def initialize(workflow)
      @workflow = workflow
    end

    # Names a stage produced at run time (`VAR: NAME=value` in its output).
    def output_variable_names = Variables.output_names(stage_outputs)

    # The variables the user set up front, without anything a stage emitted.
    def input_variables = Variables.input_only(workflow.variables, stage_outputs)

    # Edited in the UI as one `NAME=value` per line.
    def variables_text = Variables.to_text(workflow.variables)

    def variables_text=(text)
      workflow.variables = Variables.parse(text)
    end

    private

    attr_reader :workflow

    def stage_outputs = StageOutputs.new(workflow).all
  end
end
