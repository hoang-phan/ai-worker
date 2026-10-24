module Stages
  # The start path of a stage: per stage type, the branch/checkout setup and the PR-check decision. Its injected
  # launcher owns detached agent run kick-off. StageExecutor still owns the live-checkout guard, polling and error
  # rescue; the Git/Github/AiCli errors raised here propagate to its rescue.
  class StartHandler
    # Stages whose start is just the rendered prompt run detached. task: personal-project workflows with no branch or PR;
    # the agent runs in the local checkout and commits its own work (as implementation prompts run `gh pr create`).
    # jira_update: the agent moves the ticket to UAT / Releaseable via its Atlassian MCP connector.
    PROMPT_ONLY_TYPES = %w[task jira_update ci_verify pr_create].freeze

    # Stage type => BrowserTestStart kind. uat_test tests the project's UAT site; local_test uses the project's own
    # development server on the PR's branch, after the PR exists and before review.
    BROWSER_TEST_KINDS = { "uat_test" => :uat, "local_test" => :local }.freeze

    def initialize(workflow:, stage:, project:, github:, git:, prompt:, handoff:, launcher:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @prompt = prompt
      @handoff = handoff
      @launcher = launcher
    end

    def call
      case stage.stage_type
      when "implementation", "simple_implementation" then start_implementation
      when "pr_check" then run_pr_check
      when "pr_review" then start_pr_review
      when "ci_check" then start_ci_check
      when *PROMPT_ONLY_TYPES then launcher.call(prompt.body)
      when *BROWSER_TEST_KINDS.keys then start_browser_test(BROWSER_TEST_KINDS.fetch(stage.stage_type))
      when "runbook_step" then start_runbook_step
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :prompt, :handoff, :launcher

    def start_implementation
      git.create_branch!(project, workflow.branch_name)
      launcher.call(prompt.body)
    end

    def start_pr_review
      Stages::PrReviewStart.new(
        workflow: workflow, stage: stage, project: project, github: github, git: git, prompt: prompt, launcher: launcher
      ).call
    end

    def start_browser_test(kind)
      Stages::BrowserTestStart.new(
        workflow: workflow, project: project, kind: kind, prompt: prompt, git: git, launcher: launcher
      ).call
    end

    def start_ci_check
      Stages::CiCheckStart.new(stage: stage, project: project, launcher: launcher).call
    end

    def start_runbook_step
      Stages::RunbookStepStart.new(
        workflow: workflow, stage: stage, github: github, prompt: prompt, launcher: launcher
      ).call
    end

    def run_pr_check
      Stages::PrCheckRun.new(
        workflow: workflow, stage: stage, project: project, github: github, git: git,
        handoff: handoff, prompt: prompt, launcher: launcher
      ).call
    end
  end
end
