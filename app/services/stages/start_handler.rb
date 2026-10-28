module Stages
  # The start path of a stage: per stage type, the branch/checkout setup and the PR-check decision. Its injected
  # launcher owns detached agent run kick-off. StageExecutor still owns the live-checkout guard, polling and error
  # rescue; the Git/Github/AiCli errors raised here propagate to its rescue.
  class StartHandler
    # Stages whose start is just the rendered prompt run detached. task: personal-project workflows with no branch or PR;
    # the agent runs in the local checkout and commits its own work (as implementation prompts run `gh pr create`).
    # jira_update: the agent moves the ticket to UAT / Releaseable via its Atlassian MCP connector.
    PROMPT_ONLY_TYPES = %w[task jira_update ci_verify pr_create].freeze

    # Start-service class-and-collaborator-key table, keyed by stage type. Each entry is built through
    # CollaboratorFactory; browser-test rows carry their kind: as a per-entry extras hash.
    STARTERS = {
      "pr_check" => [ Stages::PrCheckRun, %i[workflow stage project github git handoff prompt launcher] ],
      "pr_review" => [ Stages::PrReviewStart, %i[workflow stage project github git prompt launcher] ],
      "ci_check" => [ Stages::CiCheckStart, %i[stage project launcher] ],
      "uat_test" => [ Stages::BrowserTestStart, %i[workflow project kind prompt git launcher], { kind: :uat }.freeze ],
      "local_test" => [ Stages::BrowserTestStart, %i[workflow project kind prompt git launcher], { kind: :local }.freeze ],
      "runbook_step" => [ Stages::RunbookStepStart, %i[workflow stage github prompt launcher] ]
    }.transform_values(&:freeze).freeze

    def initialize(workflow:, stage:, project:, github:, git:, prompt:, handoff:, launcher:, starters: STARTERS)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @prompt = prompt
      @handoff = handoff
      @launcher = launcher
      @starters = starters
    end

    def call
      case stage.stage_type
      when "implementation", "simple_implementation" then start_implementation
      when *PROMPT_ONLY_TYPES then launcher.call(prompt.body)
      else
        starter&.call
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :prompt, :handoff, :launcher, :starters

    def start_implementation
      git.create_branch!(project, workflow.branch_name)
      launcher.call(prompt.body)
    end

    def starter
      entry = starters[stage.stage_type]
      return unless entry

      CollaboratorFactory.new(collaborators).build(entry)
    end

    def collaborators
      {
        workflow: workflow, stage: stage, project: project, github: github, git: git,
        prompt: prompt, handoff: handoff, launcher: launcher
      }
    end
  end
end
