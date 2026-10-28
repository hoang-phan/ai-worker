module Workflows
  # The manual lifecycle transitions: start, resume after an error, roll back to review, and the runbook's
  # Run stage / Next guards. Each returns true when it applied and false when the workflow wasn't in a state for it.
  class Transitions
    def initialize(workflow, resume_status: Workflows::ResumeStatus.new(workflow))
      @workflow = workflow
      @resume_status = resume_status
    end

    # Pending -> implementing (a runbook starts at its first stage). False when it was already started.
    def start!
      return false unless @workflow.pending?

      @workflow.runbook? ? @workflow.start_runbook! : @workflow.update!(status: :implementing)
      true
    end

    # Errored -> the in-flight status chosen by resume_status, logging a 'resumed' StageRun. False unless errored.
    def resume!
      return false unless @workflow.errored?

      @workflow.transaction do
        @workflow.update!(status: resume_status)
        @workflow.current_stage&.log_run!("resumed")
      end
      true
    end

    def resume_status
      @resume_status.call
    end

    def can_rollback_to_review?
      @workflow.done? && @workflow.development? && @workflow.github_pr_url.present?
    end

    # Done development workflow with a PR -> reviewing, logging a 'rolled_back_to_review' StageRun.
    def rollback_to_review!
      return false unless can_rollback_to_review?

      @workflow.transaction do
        @workflow.update!(status: :reviewing)
        @workflow.current_stage&.log_run!("rolled_back_to_review")
      end
      true
    end

    # A ci_loop workflow idle in the check or verify stage can skip it, e.g. when bin/ci already ran separately.
    def can_skip_stage?
      @workflow.development? && @workflow.project.ci_loop_ready? && !@workflow.processing? &&
        (@workflow.ci_checking? || @workflow.ci_verifying?)
    end

    # The status skipping the current ci_loop stage leads to: check -> verify, verify -> local testing or review.
    def skip_status
      @workflow.ci_checking? ? :ci_verifying : @workflow.post_pr_status
    end

    # Moves on from the current ci_loop stage without running it, logging a 'stage_skipped' StageRun. Skipping the
    # check clears its stale output so the verify stage doesn't act on an earlier round's log. Skipping the verify
    # hands the PR to reviewers as a passing verify would (unless local testing comes first).
    def skip_stage!
      return false unless can_skip_stage?

      stage = @workflow.current_stage
      testing_locally = @workflow.local_test_before_review?
      verifying = @workflow.ci_verifying?
      @workflow.transaction do
        @workflow.update!(status: skip_status, **(verifying ? {} : { ci_output_path: nil, ci_exit_status: nil }))
        stage&.log_run!("stage_skipped")
      end
      Stages::ReviewHandoff.new(@workflow, stage).notify_reviewers! if verifying && !testing_locally && stage
      true
    end

    # The runbook's "Run stage" button is only valid on an implementing runbook that isn't mid-run.
    def can_run_stage?
      @workflow.runbook? && @workflow.implementing? && !@workflow.processing?
    end

    # Flags the runbook so the scheduler runs its current stage and carries on. False when no stage is ready.
    # The caller enqueues WorkflowSchedulerJob.
    def request_stage_run!
      return false unless can_run_stage?

      @workflow.update!(auto_run: true)
      true
    end

    # The runbook's Next button is only valid while a finished stage is waiting for it.
    def can_advance?
      @workflow.runbook? && @workflow.awaiting_next?
    end
  end
end
