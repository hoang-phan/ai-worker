module Stages
  # The success path of an implementation run: the run opened the PR itself, see Stages::PrOpenedFinish.
  class ImplementationFinish
    def initialize(workflow:, stage:, project:, github:, handoff:)
      @pr_opened_finish = Stages::PrOpenedFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
    end

    def call(output)
      @pr_opened_finish.call(output, action: "ran_implementation")
    end
  end
end
