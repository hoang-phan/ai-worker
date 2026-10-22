module Workflows
  # The manual lifecycle transitions: start, resume after an error, roll back to review, and the runbook's
  # Run stage / Next guards. Each returns true when it applied and false when the workflow wasn't in a state for it.
  class Transitions
    def initialize(workflow)
      @workflow = workflow
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

    # The in-flight status an errored workflow goes back to: reviewing once a PR
    # exists (personal-project and PR-review workflows never reach it), otherwise implementing.
    def resume_status
      return :uat_testing if @workflow.uat_test_at.present?
      ci_status = Workflows::CiLoopResume.new(@workflow).status
      return ci_status if ci_status
      return :local_testing if local_test_unfinished?

      @workflow.development? && @workflow.github_pr_url.present? ? :reviewing : :implementing
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

    private

    # An errored workflow whose newest local test run started but never finished goes back to it, not to review
    # (also true for a retest after a fix round: earlier completed rounds don't count).
    def local_test_unfinished?
      @workflow.stages.find_by(stage_type: :local_test)&.local_test_unfinished? || false
    end
  end
end
