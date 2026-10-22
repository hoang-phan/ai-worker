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
      case stage.stage_type
      when "implementation" then Stages::ImplementationFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
      when "pr_check" then Stages::PrCheckFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
      when "task" then Stages::TaskFinish.new(workflow: workflow, stage: stage, project: project, git: git).call(output)
      when "pr_review" then Stages::PrReviewFinish.new(workflow: workflow, stage: stage).call(output)
      when "jira_update" then Stages::JiraUpdateFinish.new(workflow: workflow, stage: stage, project: project).call(output)
      when "uat_test" then Stages::UatTestFinish.new(workflow: workflow, stage: stage).call(output)
      when "local_test" then Stages::LocalTestFinish.new(workflow: workflow, stage: stage, handoff: handoff).call(output)
      when "ci_check" then Stages::CiCheckFinish.new(workflow: workflow, stage: stage).call(output)
      when "simple_implementation" then Stages::SimpleImplementationFinish.new(workflow: workflow, stage: stage).call(output)
      when "ci_verify" then Stages::CiVerifyFinish.new(workflow: workflow, stage: stage, project: project, handoff: handoff).call(output)
      when "pr_create" then Stages::PrOpenedFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output, action: "pr_created", checks_follow: project.ci_loop_ready?)
      when "runbook_step" then Stages::RunbookStepFinish.new(workflow: workflow, stage: stage).call(output)
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :handoff
  end
end
