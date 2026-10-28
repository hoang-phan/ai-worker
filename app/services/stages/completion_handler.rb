module Stages
  # The success path of a finished agent run: per stage type, the Workflow/StageRun mutations and the best-effort
  # follow-ups (auto-merge, reviewer notification, task push). StageExecutor still owns polling, logging setup and
  # error rescue; the AiCli::CommandErrors raised here for missing result markers propagate to its rescue.
  class CompletionHandler
    FINISHERS = {
      "implementation" => [ Stages::ImplementationFinish, %i[workflow stage project github handoff] ],
      "pr_check" => [ Stages::PrCheckFinish, %i[workflow stage project github handoff] ],
      "task" => [ Stages::TaskFinish, %i[workflow stage project git] ],
      "pr_review" => [ Stages::PrReviewFinish, %i[workflow stage] ],
      "jira_update" => [ Stages::JiraUpdateFinish, %i[workflow stage project] ],
      "uat_test" => [ Stages::UatTestFinish, %i[workflow stage] ],
      "local_test" => [ Stages::LocalTestFinish, %i[workflow stage handoff] ],
      "ci_check" => [ Stages::CiCheckFinish, %i[workflow stage] ],
      "simple_implementation" => [ Stages::SimpleImplementationFinish, %i[workflow stage] ],
      "ci_verify" => [ Stages::CiVerifyFinish, %i[workflow stage project handoff] ],
      "pr_create" => [ Stages::PrCreateFinish, %i[workflow stage project github handoff] ],
      "runbook_step" => [ Stages::RunbookStepFinish, %i[workflow stage] ]
    }.transform_values(&:freeze).freeze

    def initialize(workflow:, stage:, project:, github:, git:, handoff:, finishers: FINISHERS)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @handoff = handoff
      @finishers = finishers
    end

    def call(output)
      finisher&.call(output)
    end

    private

    def finisher
      entry = finishers[stage.stage_type]
      return unless entry

      CollaboratorFactory.new(collaborators).build(entry)
    end

    def collaborators
      { workflow: workflow, stage: stage, project: project, github: github, git: git, handoff: handoff }
    end

    attr_reader :workflow, :stage, :project, :github, :git, :handoff, :finishers
  end
end
