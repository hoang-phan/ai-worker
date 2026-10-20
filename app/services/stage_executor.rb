class StageExecutor
  # How long a background the agent CLI run is allowed to sit without
  # finishing before we give up on it and mark the stage failed. Guards
  # against a hung/orphaned process blocking this workflow forever.
  STALE_AFTER = 3.hours

  # After this many consecutive `failed` runs for a stage the workflow is
  # parked as `errored` (each retry is a full agent CLI run), so the scheduler
  # moves on to the next workflow until someone resumes it — see docs/RUNBOOK.md.
  MAX_CONSECUTIVE_FAILURES = 3

  # A FAILED local test is fixed by the next pr_check run and then tested again, at most this many tests in total;
  # after that the PR just goes to review with the last failure noted on it.
  MAX_LOCAL_TEST_ROUNDS = 3

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
    return unless check_passed?

    start_ai_run(stage.run_message? ? prompt.slack_message(prompt.body) : prompt.body)
  end

  # A stage with `wait_for_workflow` doesn't start until the newest run of that GitHub Actions workflow (started
  # after the previous stage began, so an older deploy can't satisfy it) has finished successfully — like pr_check, it
  # is re-checked every tick and logs once. A finished-but-failed run fails the stage instead of waiting forever.
  def check_passed?
    return true if stage.wait_for_workflow.blank?

    state = Github::Client.new(project).workflow_run_state(stage.wait_for_workflow, since: check_since, repo: workflow.variables["REPO"])
    case state[:state]
    when :success
      log(action: "check_passed", output: state[:url])
      true
    when :failed
      raise Github::CommandError, "GitHub Actions #{stage.wait_for_workflow} finished with #{state[:conclusion]}: #{state[:url]}"
    else
      log(action: "waiting_for_check", output: state[:url]) unless stage.last_action == "waiting_for_check"
      false
    end
  end

  def check_since
    previous = workflow.previous_runbook_stage
    previous&.stage_runs&.where(action: "started")&.maximum(:created_at) || workflow.created_at
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

    case stage.stage_type
    when "implementation"
      pr_url = Github::Client.new(project).find_pr_url(
        branch_name: workflow.branch_name, jira_ticket: workflow.jira_ticket, output: output
      )
      testing_locally = workflow.development? && project.local_test_ready?
      workflow.update!(ai_run_attrs.merge(github_pr_url: pr_url, status: testing_locally ? :local_testing : :reviewing))
      log(action: "ran_implementation", output: output)
      # Auto-merge waits until the local test passed, so a PR can't merge while it is still being tested.
      handoff.enable_auto_merge!(pr_url) unless testing_locally
      handoff.notify_reviewers! unless testing_locally
    when "pr_check"
      Github::Client.new(project).request_review!(workflow.github_pr_url, reviewers)
      retest = local_retest?(output)
      workflow.update!(ai_run_attrs.merge(local_test_feedback: nil, **(retest ? { status: :local_testing } : {})))
      log(action: "requested_changes_fixed", output: output)
      log(action: "local_test_retest_scheduled") if retest
      handoff.notify_reviewers!(again: true, fixed: AiCli::Output.new(output).fixed_summary) unless retest
    when "task"
      workflow.update!(ai_run_attrs.merge(status: :done))
      log(action: "task_completed", output: output)
      push_task_commits
    when "pr_review"
      workflow.update!(ai_run_attrs.merge(status: :done))
      log(action: "review_completed", output: output)
    when "jira_update"
      finish_jira_update(output)
    when "uat_test"
      finish_uat_test(output)
    when "local_test"
      finish_local_test(output)
    when "runbook_step"
      finish_runbook_step(output)
    end
  end

  # The workflow parks in `waiting` until someone clicks Next (Workflow#advance!), unless the stage is
  # `auto_advance`: then it moves straight on and the scheduler starts the next stage. Agents can hand values to later stages with lines like
  # `VAR: VERSION=2.21.1-f839742`, which become workflow variables / {VERSION}.
  def finish_runbook_step(output)
    if stage.run_message? && !AiCli::Output.new(output).posted?
      raise AiCli::CommandError, "agent finished without confirming the Slack message was posted (no POSTED line)"
    end

    workflow.update!(ai_run_attrs.merge(status: :waiting, awaiting_next: true,
                                         variables: workflow.variables.merge(AiCli::Output.new(output).variables)))
    log(action: "stage_completed", output: output)
    log(action: "message_sent") if stage.run_message?
    return unless stage.auto_advance?

    workflow.advance!
    WorkflowSchedulerJob.perform_later(workflow.id) if workflow.auto_run?
  end

  # The prompt makes the agent end with `JIRA_RESULT: UAT` or
  # `JIRA_RESULT: RELEASEABLE`; without it we can't tell the ticket moved.
  def finish_jira_update(output)
    outcome = AiCli::Output.new(output).jira_result
    raise AiCli::CommandError, "agent finished without a JIRA_RESULT line, treating the Jira update as failed" unless outcome

    # A ticket that went to UAT is tested by the agent after the project's delay, if the project opted in.
    if outcome.casecmp?("UAT") && project.uat_test_ready?
      run_at = project.uat_test_delay_minutes.minutes.from_now
      workflow.update!(ai_run_attrs.merge(status: :uat_waiting, uat_test_at: run_at))
      log(action: "jira_updated", output: output)
      log(action: "uat_test_scheduled", output: "UAT test scheduled for #{run_at.iso8601}")
    else
      workflow.update!(ai_run_attrs.merge(status: :jira_updated))
      log(action: "jira_updated", output: output)
    end
  end

  # The prompt makes the agent end with `UAT_RESULT: PASSED|FAILED|BLOCKED` once its comment is on the ticket. Any of
  # the three is a finished test (the verdict lives in the comment and this log); no line means we can't tell the
  # comment was posted, so the stage fails and retries like any other.
  def finish_uat_test(output)
    result = AiCli::Output.new(output).uat_result
    raise AiCli::CommandError, "agent finished without a UAT_RESULT line, treating the UAT test as failed" unless result

    workflow.update!(ai_run_attrs.merge(status: :uat_tested))
    log(action: "uat_test_completed", output: output)
  end

  # The prompt makes the agent end with `LOCAL_TEST_RESULT: PASSED|FAILED|BLOCKED` once its PR comment is posted.
  # Whatever the verdict the PR goes on to review (a person sees the comment); only PASSED turns on auto-merge.
  # After a fix run: test again (while the reviewer looks at the new push) when a local failure was being fixed, or the
  # agent says the changes touched behaviour (the review may have changed the flow the last test covered). A missing
  # LOCAL_RETEST line counts as YES. Rounds are capped like any local test.
  def local_retest?(output)
    return false unless project.local_test_ready?

    rounds = workflow.stages.find_by(stage_type: :local_test)&.completed_local_test_rounds.to_i
    return false if rounds >= MAX_LOCAL_TEST_ROUNDS

    workflow.local_test_feedback.present? || AiCli::Output.new(output).retest_requested?
  end

  def finish_local_test(output)
    result = AiCli::Output.new(output).local_test_result
    raise AiCli::CommandError, "agent finished without a LOCAL_TEST_RESULT line, treating the local test as failed" unless result

    failed = result.casecmp?("FAILED")
    rounds = stage.completed_local_test_rounds + 1
    retest = failed && rounds < MAX_LOCAL_TEST_ROUNDS
    workflow.update!(ai_run_attrs.merge(status: :reviewing, local_test_feedback: retest ? local_test_feedback(output) : nil))
    log(action: "local_test_completed", output: output)
    log(action: "local_test_rounds_exhausted") if failed && !retest
    handoff.enable_auto_merge!(workflow.github_pr_url) if result.casecmp?("PASSED")
    handoff.notify_reviewers!
  end

  # The block the agent printed between the markers (the last one: the log may echo the prompt's own example),
  # or a pointer to its PR comment.
  def local_test_feedback(output)
    AiCli::Output.new(output).local_test_feedback_block ||
      "Local testing failed; see the \"Local test by agent\" comment on #{workflow.github_pr_url} for the failing steps."
  end

  # The conflict-resolution run must leave the merge committed; only then does
  # the review-fix prompt run (immediately, in the same tick).
  def finish_conflict_resolution(output)
    if Git::BranchService.merge_in_progress?(project)
      Git::BranchService.abort_merge!(project)
      raise AiCli::CommandError, "#{AiCli::Runner.agent} did not finish resolving merge conflicts with main"
    end

    workflow.update!(ai_run_attrs)
    log(action: "conflicts_resolved", output: output)
    start_ai_run(prompt.body)
  end

  # The task prompt may or may not tell the agent to push, so do it here. Best effort and after the workflow is
  # `done`: a failed push is logged, never fails the stage (a retry would re-run the whole task).
  def push_task_commits
    log(action: "task_pushed") if Git::BranchService.push_current!(project) == :pushed
  rescue Git::CommandError => e
    log(action: "task_push_failed", error: e.message)
  end

  # A failure stays in the current status so the next tick retries it, until
  # MAX_CONSECUTIVE_FAILURES in a row park the workflow in `errored`, which
  # WorkflowSchedulerJob ignores. A person resumes it from the UI once the
  # cause is fixed.
  def fail_stage(error)
    Git::BranchService.abort_merge!(project) if stage.resolving_conflicts?
    workflow.update!(ai_run_attrs.merge(auto_run: false))
    log(action: "failed", error: error.message)
    workflow.update!(status: :errored) if stage.consecutive_failures >= MAX_CONSECUTIVE_FAILURES
  end

  def ai_run_attrs
    {
      processing: false,
      ai_pid: nil,
      ai_log_path: nil,
      ai_started_at: nil,
      ai_log_offset: 0
    }
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
