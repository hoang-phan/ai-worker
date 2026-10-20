class StageExecutor
  # How long a background the agent CLI run is allowed to sit without
  # finishing before we give up on it and mark the stage failed. Guards
  # against a hung/orphaned process blocking this workflow forever.
  STALE_AFTER = 3.hours

  # After this many consecutive `failed` runs for a stage the workflow is
  # parked as `errored` (each retry is a full agent CLI run), so the scheduler
  # moves on to the next workflow until someone resumes it — see docs/RUNBOOK.md.
  MAX_CONSECUTIVE_FAILURES = 3

  def initialize(workflow, stage)
    @workflow = workflow
    @stage = stage
    @project = workflow.project
  end

  def call
    raise ArgumentError, "project #{project.name} points at the live ai-worker checkout; use a separate clone" if project.runs_from_live_checkout?

    if workflow.processing?
      poll_ai_run
    else
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
  rescue Git::CommandError, Github::CommandError, AiCli::CommandError, ArgumentError => e
    fail_stage(e)
  end

  # A `done` workflow whose PR has since been merged becomes `merged`. Called
  # by the scheduler only on idle ticks. A failed lookup is logged and retried
  # next idle tick — it never fails the workflow.
  def check_merged
    return unless Github::Client.new(project).merged?(workflow.github_pr_url)

    workflow.update!(status: :merged)
    log(action: "pr_merged_detected")
  rescue Github::CommandError => e
    log(action: "merge_check_failed", error: e.message)
  end

  private

  attr_reader :workflow, :stage, :project

  def start_implementation
    Git::BranchService.create_branch!(project, workflow.branch_name)
    start_ai_run(prompt.body)
  end

  # Personal-project workflows: no branch, no PR — just run the agent CLI
  # directly against the project's local checkout (already on its own
  # branch/main) and commit. The task-stage prompt instructs the agent to
  # commit its own work, the same way implementation-stage prompts
  # instruct it to run `gh pr create` itself.
  def start_task
    start_ai_run(prompt.body)
  end

  # Someone else's PR (found in a Slack mention): put the clone on its head
  # branch for context, then let the agent review it, post the GitHub verdict
  # and reply in the Slack thread — the prompt tells it to do all three.
  def start_pr_review
    github = Github::Client.new(project)
    info = github.pr_info(workflow.github_pr_url)

    unless info["state"] == "OPEN"
      workflow.update!(status: :done)
      return log(action: "pr_not_open_skipped")
    end

    if info["cross_repository"]
      github.checkout_pr!(workflow.github_pr_url)
    else
      Git::BranchService.checkout_remote_branch!(project, info["head_ref"])
    end
    start_ai_run(prompt.body)
  end

  # Moves the ticket to UAT / Releaseable via the agent's Atlassian MCP
  # connector (it decides which, from the PR). Runs detached like any agent run.
  def start_jira_update
    start_ai_run(prompt.body)
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
    Git::BranchService.checkout_remote_branch!(project, workflow.branch_name)
    start_browser_test(run)
  end

  def start_browser_test(run)
    start_ai_run(prompt.body, mcp_config: run.mcp_config_path, env: run.env, disallowed_tools: run.disallowed_tools)
  end

  # Runbook stages are plain agent runs: `agent` runs the prompt as written,
  # `message` has the agent post the rendered text to Slack via its MCP connector.
  # Either way the workflow then waits for a person to click Next (finish_runbook_step).
  def start_runbook_step
    return unless Stages::WorkflowRunGate.new(workflow: workflow, stage: stage, github: Github::Client.new(project)).call.passed?

    start_ai_run(stage.run_message? ? prompt.slack_message(prompt.body) : prompt.body)
  end

  def run_pr_check
    github = Github::Client.new(project)

    # A merged PR is done — skip review/check inspection entirely.
    if github.merged?(workflow.github_pr_url)
      workflow.update!(status: :merged)
      return log(action: "pr_merged_closed")
    end

    result = Stages::PrCheckDecision.new(
      review_decision: github.review_decision(workflow.github_pr_url, reviewers),
      local_test_failing: workflow.local_test_feedback.present?,
      checks_failing: -> { github.checks_failing?(workflow.github_pr_url) }
    ).call
    result.actions.each { |action| log(action: action) }

    case result.decision
    when :approved
      workflow.update!(status: :done)
      log(action: "approved_closed")
    when :changes_requested
      if Git::BranchService.update_with_main!(project, workflow.branch_name) == :conflict
        start_ai_run(Prompts::StagePrompt::CONFLICT, action: "conflict_resolution_started")
      else
        start_ai_run(prompt.body)
      end
    else
      log(action: "no_action_pending")
    end
  end

  # Kicks off the agent CLI in the background and returns immediately —
  # the run itself can take longer than Sidekiq's job timeout. Marks
  # the workflow as processing so WorkflowSchedulerJob polls it instead
  # of starting new work on the next tick.
  def start_ai_run(prompt, action: "started", mcp_config: nil, env: {}, disallowed_tools: [])
    log_path = new_log_path
    pid = AiCli::Runner.start(project.local_directory, prompt, log_path: log_path, mcp_config: mcp_config, env: env, disallowed_tools: disallowed_tools)

    workflow.update!(
      processing: true,
      ai_pid: pid,
      ai_log_path: log_path,
      ai_started_at: Time.current,
      ai_log_offset: 0
    )
    log(action: action)
  end

  def poll_ai_run
    poller = AiCli::RunPoller.new(
      pid: workflow.ai_pid, log_path: workflow.ai_log_path, log_offset: workflow.ai_log_offset,
      started_at: workflow.ai_started_at, log_tag: log_tag, stale_after: STALE_AFTER
    )
    begin
      state, output = poller.call
    ensure
      workflow.update_column(:ai_log_offset, poller.log_offset) if poller.log_offset != workflow.ai_log_offset
    end
    return if state == :running

    finalize_success(output)
  end

  def finalize_success(output)
    return finish_conflict_resolution(output) if stage.resolving_conflicts?

    Stages::CompletionHandler.new(
      workflow: workflow, stage: stage, project: project,
      github: Github::Client.new(project), git: Git::BranchService, handoff: handoff
    ).call(output)
  end

  # The conflict-resolution run must leave the merge committed; only then does
  # the review-fix prompt run (immediately, in the same tick).
  def finish_conflict_resolution(output)
    if Git::BranchService.merge_in_progress?(project)
      Git::BranchService.abort_merge!(project)
      raise AiCli::CommandError, "#{AiCli::Runner.agent} did not finish resolving merge conflicts with main"
    end

    workflow.update!(Workflow::AI_RUN_RESET)
    log(action: "conflicts_resolved", output: output)
    start_ai_run(prompt.body)
  end

  def fail_stage(error)
    Stages::FailureHandler.new(
      workflow: workflow, stage: stage, project: project, error: error, threshold: MAX_CONSECUTIVE_FAILURES
    ).call
  end

  def new_log_path
    Rails.root.join("log", "ai_runs", "workflow-#{workflow.id}-#{Time.current.to_i}.log").to_s
  end

  def log_tag
    "workflow=#{workflow.id} stage=#{stage.id}"
  end

  def reviewers
    handoff.reviewers
  end

  def handoff
    @handoff ||= Stages::ReviewHandoff.new(workflow, stage)
  end

  def prompt
    @prompt ||= Prompts::StagePrompt.new(workflow, stage)
  end

  def log(action:, output: nil, error: nil)
    stage.stage_runs.create!(action: action, output: output, error: error)
  end
end
