module Stages
  # The success path of a finished agent run: per stage type, the Workflow/StageRun mutations and the best-effort
  # follow-ups (auto-merge, reviewer notification, task push). StageExecutor still owns polling, logging setup and
  # error rescue; the AiCli::CommandErrors raised here for missing result markers propagate to its rescue.
  class CompletionHandler
    def initialize(workflow:, stage:, project:, github:, git:, handoff:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @handoff = handoff
    end

    def call(output)
      finisher&.call(output)
    end

    private

    def finisher
      case stage.stage_type
      when "implementation"
        Stages::ImplementationFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
      when "pr_check"
        Stages::PrCheckFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
      when "task"
        Stages::TaskFinish.new(workflow: workflow, stage: stage, project: project, git: git)
      when "pr_review"
        Stages::PrReviewFinish.new(workflow: workflow, stage: stage)
      when "jira_update"
        Stages::JiraUpdateFinish.new(workflow: workflow, stage: stage, project: project)
      when "uat_test"
        Stages::UatTestFinish.new(workflow: workflow, stage: stage)
      when "local_test"
        Stages::LocalTestFinish.new(workflow: workflow, stage: stage, handoff: handoff)
      when "ci_check"
        Stages::CiCheckFinish.new(workflow: workflow, stage: stage)
      when "simple_implementation"
        Stages::SimpleImplementationFinish.new(workflow: workflow, stage: stage)
      when "ci_verify"
        Stages::CiVerifyFinish.new(workflow: workflow, stage: stage, project: project, handoff: handoff)
      when "pr_create"
        Stages::PrCreateFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
      when "runbook_step"
        Stages::RunbookStepFinish.new(workflow: workflow, stage: stage)
      end
    end

    attr_reader :workflow, :stage, :project, :github, :git, :handoff
  end
end
