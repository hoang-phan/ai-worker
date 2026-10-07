class StageExecutor
  # How long a background the agent CLI run is allowed to sit without
  # finishing before we give up on it and mark the stage failed. Guards
  # against a hung/orphaned process blocking this workflow forever.
  STALE_AFTER = 3.hours

  # After this many consecutive `failed` runs for a stage, stop retrying
  # (each retry is a full the agent CLI run) until someone logs a `resumed`
  # StageRun — see docs/RUNBOOK.md.
  MAX_CONSECUTIVE_FAILURES = 3

  def initialize(workflow, stage)
    @workflow = workflow
    @stage = stage
    @project = workflow.project
  end

  def call
    if workflow.processing?
      poll_ai_run
    elsif halted?
      log_halted
    else
      case stage.stage_type
      when "implementation" then start_implementation
      when "pr_check" then run_pr_check
      when "task" then start_task
      end
    end
  rescue Git::CommandError, Github::CommandError, AiCli::CommandError, ArgumentError => e
    fail_stage(e)
  end

  private

  attr_reader :workflow, :stage, :project

  def start_implementation
    Git::BranchService.create_branch!(project, workflow.branch_name)
    start_ai_run(render_prompt)
  end

  # Personal-project workflows: no branch, no PR — just run the agent CLI
  # directly against the project's local checkout (already on its own
  # branch/main) and commit. The task-stage prompt instructs the agent to
  # commit its own work, the same way implementation-stage prompts
  # instruct it to run `gh pr create` itself.
  def start_task
    start_ai_run(render_prompt)
  end

  def run_pr_check
    github = Github::Client.new(project)
    decision = github.review_decision(workflow.github_pr_url, reviewers)

    case decision
    when "APPROVED"
      workflow.update!(status: :done)
      log(action: "approved_closed")
    when "CHANGES_REQUESTED"
      Git::BranchService.create_branch!(project, workflow.branch_name)
      start_ai_run(render_prompt)
    else
      log(action: "no_action_pending")
    end
  end

  # Kicks off the agent CLI in the background and returns immediately —
  # the run itself can take longer than Sidekiq's job timeout. Marks
  # the workflow as processing so WorkflowSchedulerJob polls it instead
  # of starting new work on the next tick.
  def start_ai_run(prompt)
    log_path = new_log_path
    pid = AiCli::Runner.start(project.local_directory, prompt, log_path: log_path, agent: workflow.agent)

    workflow.update!(
      processing: true,
      ai_pid: pid,
      ai_log_path: log_path,
      ai_started_at: Time.current,
      ai_log_offset: 0
    )
    log(action: "started")
  end

  def poll_ai_run
    if stale?
      kill_stale_run
      raise AiCli::CommandError, "#{workflow.agent} timed out after #{STALE_AFTER.inspect} (pid=#{workflow.ai_pid})"
    end

    tail_log
    result = AiCli::Runner.poll(workflow.ai_pid)
    return if result == :running

    _tag, exit_status = result
    tail_log
    output = full_log

    unless exit_status.nil? || exit_status.success?
      raise AiCli::CommandError, "#{workflow.agent} failed (pid=#{workflow.ai_pid}): #{output.presence || 'no output'}"
    end
    raise AiCli::CommandError, "#{workflow.agent} exit status unknown (pid=#{workflow.ai_pid}), treating as failed" if exit_status.nil?

    finalize_success(output)
  end

  def finalize_success(output)
    case stage.stage_type
    when "implementation"
      pr_url = Github::Client.new(project).find_pr_url(
        branch_name: workflow.branch_name, jira_ticket: workflow.jira_ticket, output: output
      )
      workflow.update!(ai_run_attrs.merge(github_pr_url: pr_url, status: :reviewing))
      log(action: "ran_implementation", output: output)
      enable_auto_merge(pr_url)
    when "pr_check"
      Github::Client.new(project).request_review!(workflow.github_pr_url, reviewers)
      workflow.update!(ai_run_attrs)
      log(action: "requested_changes_fixed", output: output)
    when "task"
      workflow.update!(ai_run_attrs.merge(status: :done))
      log(action: "task_completed", output: output)
    end
  end

  # Best-effort, and run only after the workflow has moved to `reviewing`:
  # a failure here (e.g. auto-merge disabled on the repo) must not fail the
  # stage, or the retry would re-run the whole implementation.
  def enable_auto_merge(pr_url)
    Github::Client.new(project).enable_auto_merge!(pr_url)
    log(action: "auto_merge_enabled")
  rescue Github::CommandError => e
    log(action: "auto_merge_failed", error: e.message)
  end

  def fail_stage(error)
    workflow.update!(ai_run_attrs)
    log(action: "failed", error: error.message)
  end

  # Trailing run of failed/started/halted rows (newest first) with no
  # success or `resumed` in between.
  def consecutive_failures
    stage.stage_runs.order(id: :desc).pluck(:action)
         .take_while { |action| %w[failed started halted].include?(action) }
         .count("failed")
  end

  def halted?
    consecutive_failures >= MAX_CONSECUTIVE_FAILURES
  end

  # Logged once, not on every tick.
  def log_halted
    return if stage.stage_runs.order(:id).last&.action == "halted"

    log(action: "halted", error: "#{MAX_CONSECUTIVE_FAILURES} consecutive failures — not retrying until a `resumed` StageRun is logged")
  end

  def tail_log
    return unless workflow.ai_log_path

    _content, new_offset = AiCli::Runner.tail_new_lines(
      workflow.ai_log_path, from_offset: workflow.ai_log_offset, log_tag: log_tag
    )
    workflow.update_column(:ai_log_offset, new_offset) if new_offset != workflow.ai_log_offset
  end

  def full_log
    return "" unless workflow.ai_log_path && File.exist?(workflow.ai_log_path)

    File.read(workflow.ai_log_path)
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

  def stale?
    workflow.ai_started_at.present? && workflow.ai_started_at < STALE_AFTER.ago
  end

  def kill_stale_run
    Process.kill("TERM", workflow.ai_pid)
  rescue Errno::ESRCH
    nil
  end

  def new_log_path
    Rails.root.join("log", "ai_runs", "workflow-#{workflow.id}-#{Time.current.to_i}.log").to_s
  end

  def log_tag
    "workflow=#{workflow.id} stage=#{stage.id}"
  end

  def reviewers
    Github::Client.parse_reviewers(workflow.github_reviewer)
  end

  def render_prompt
    body = stage.prompt.presence || stage.effective_template&.body
    raise ArgumentError, "no prompt available for stage #{stage.id}" unless body

    Prompts::Renderer.render(body, workflow)
  end

  def log(action:, output: nil, error: nil)
    stage.stage_runs.create!(action: action, output: output, error: error)
  end
end
