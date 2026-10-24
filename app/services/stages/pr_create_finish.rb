module Stages
  # The success path of a pr_create run: it always records the PR action, and ci_loop projects check it before review.
  class PrCreateFinish
    def initialize(workflow:, stage:, project:, github:, handoff:)
      @project = project
      @pr_opened_finish = Stages::PrOpenedFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
    end

    def call(output)
      @pr_opened_finish.call(output, action: "pr_created", checks_follow: project.ci_loop_ready?)
    end

    private

    attr_reader :project
  end
end
