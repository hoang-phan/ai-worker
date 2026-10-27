module Stages
  # The success path of a finished agent run: per stage type, the Workflow/StageRun mutations and the best-effort
  # follow-ups (auto-merge, reviewer notification, task push). StageExecutor still owns polling, logging setup and
  # error rescue; the AiCli::CommandErrors raised here for missing result markers propagate to its rescue.
  class CompletionHandler
    FINISHERS = {
      "implementation" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::ImplementationFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
      },
      "pr_check" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::PrCheckFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
      },
      "task" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::TaskFinish.new(workflow: workflow, stage: stage, project: project, git: git)
      },
      "pr_review" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::PrReviewFinish.new(workflow: workflow, stage: stage)
      },
      "jira_update" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::JiraUpdateFinish.new(workflow: workflow, stage: stage, project: project)
      },
      "uat_test" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::UatTestFinish.new(workflow: workflow, stage: stage)
      },
      "local_test" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::LocalTestFinish.new(workflow: workflow, stage: stage, handoff: handoff)
      },
      "ci_check" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::CiCheckFinish.new(workflow: workflow, stage: stage)
      },
      "simple_implementation" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::SimpleImplementationFinish.new(workflow: workflow, stage: stage)
      },
      "ci_verify" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::CiVerifyFinish.new(workflow: workflow, stage: stage, project: project, handoff: handoff)
      },
      "pr_create" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::PrCreateFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
      },
      "runbook_step" => lambda { |workflow:, stage:, project:, github:, git:, handoff:|
        Stages::RunbookStepFinish.new(workflow: workflow, stage: stage)
      }
    }.freeze

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
      finishers[stage.stage_type]&.call(workflow: workflow, stage: stage, project: project, github: github, git: git, handoff: handoff)
    end

    attr_reader :workflow, :stage, :project, :github, :git, :handoff, :finishers
  end
end
