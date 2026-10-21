module Stages
  # The start path of a stage: per stage type, the branch/checkout setup and the PR-check decision. Its injected
  # launcher owns detached agent run kick-off. StageExecutor still owns the live-checkout guard, polling and error
  # rescue; the Git/Github/AiCli errors raised here propagate to its rescue.
  class StartHandler
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
      when "implementation" then start_implementation
      when "pr_check" then run_pr_check
      when "task" then start_task
      when "pr_review" then start_pr_review
      when "jira_update" then start_jira_update
      when "uat_test" then start_uat_test
      when "local_test" then start_local_test
      when "runbook_step" then start_runbook_step
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :prompt, :handoff, :launcher

    def start_implementation
      git.create_branch!(project, workflow.branch_name)
      launcher.call(prompt.body)
    end

    # Personal-project workflows: no branch, no PR — just run the agent CLI
    # directly against the project's local checkout (already on its own
    # branch/main) and commit. The task-stage prompt instructs the agent to
    # commit its own work, the same way implementation-stage prompts
    # instruct it to run `gh pr create` itself.
    def start_task
      launcher.call(prompt.body)
    end

    # Someone else's PR (found in a Slack mention): put the clone on its head
    # branch for context, then let the agent review it, post the GitHub verdict
    # and reply in the Slack thread — the prompt tells it to do all three.
    def start_pr_review
      info = github.pr_info(workflow.github_pr_url)

      unless info["state"] == "OPEN"
        workflow.update!(status: :done)
        return stage.log_run!("pr_not_open_skipped")
      end

      if info["cross_repository"]
        github.checkout_pr!(workflow.github_pr_url)
      else
        git.checkout_remote_branch!(project, info["head_ref"])
      end
      launcher.call(prompt.body)
    end

    # Moves the ticket to UAT / Releaseable via the agent's Atlassian MCP
    # connector (it decides which, from the PR). Runs detached like any agent run.
    def start_jira_update
      launcher.call(prompt.body)
    end

    # The agent tests the ticket in a headless browser (Playwright MCP) on the project's UAT site, records
    # video + trace, attaches them to the ticket and comments with the result (the prompt tells it to). The browser
    # server, its output directory and the UAT/Jira credentials are wired in per run; credentials only travel as
    # environment variables of the agent process, never in the prompt or the logs we write.
    def start_uat_test
      run = AiCli::BrowserTestRun.new(project, workflow, kind: :uat).validate!
      start_browser_test(run)
    end

    # Same browser setup as the UAT test, but against the project's own development server, on the PR's branch, after the
    # PR exists and before review. The local login travels as environment variables only, like the UAT one.
    def start_local_test
      run = AiCli::BrowserTestRun.new(project, workflow, kind: :local).validate!
      git.checkout_remote_branch!(project, workflow.branch_name)
      start_browser_test(run)
    end

    def start_browser_test(run)
      launcher.call(prompt.body, mcp_config: run.mcp_config_path, env: run.env, disallowed_tools: run.disallowed_tools)
    end

    # Runbook stages are plain agent runs: `agent` runs the prompt as written,
    # `message` has the agent post the rendered text to Slack via its MCP connector.
    # Either way the workflow then waits for a person to click Next (finish_runbook_step).
    def start_runbook_step
      return unless Stages::WorkflowRunGate.new(workflow: workflow, stage: stage, github: github).call.passed?

      launcher.call(stage.run_message? ? prompt.slack_message(prompt.body) : prompt.body)
    end

    def run_pr_check
      Stages::PrCheckRun.new(
        workflow: workflow, stage: stage, project: project, github: github, git: git,
        handoff: handoff, prompt: prompt, start_ai_run: launcher
      ).call
    end
  end
end
