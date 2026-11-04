module Workflows
  # The manual lifecycle transitions: start, resume after an error, roll back to review, and the runbook's
  # Run stage / Next guards. Each returns true when it applied and false when the workflow wasn't in a state for it.
  class Transitions
    def initialize(workflow, resume_status: Workflows::ResumeStatus.new(workflow), flow: Workflows::StageFlow.new(workflow))
      @workflow = workflow
      @resume_status = resume_status
      @flow = flow
    end

    # Pending -> the first stage of the pipeline (a runbook starts at its first stage). False when already started.
    def start!
      return false unless @workflow.pending?
      if @workflow.runbook?
        @workflow.start_runbook!
      elsif (first = @flow.first_stage)
        @flow.enter!(first)
      else
        @workflow.update!(status: :implementing)
      end
      true
    end

    # Errored -> the stage chosen by ResumeStatus (and its status), logging a 'resumed' StageRun on it and on the stage
    # that errored when that is another one. False unless errored.
    def resume!
      return false unless @workflow.errored?

      target = @resume_status.call
      @workflow.transaction do
        @workflow.update!(status: target.status, **(target.stage ? { current_stage_id: target.stage.id } : {}))
        [ target.origin, @workflow.current_stage ].compact.uniq.each { |stage| stage.log_run!("resumed") }
      end
      true
    end

    def resume_status
      @resume_status.call.status
    end

    def can_rollback_to_review?
      @workflow.done? && @workflow.development? && @workflow.github_pr_url.present?
    end

    # Done development workflow with a PR -> reviewing, logging a 'rolled_back_to_review' StageRun.
    def rollback_to_review!
      return false unless can_rollback_to_review?

      @workflow.transaction do
        review = @workflow.stages.find_by(stage_type: :pr_check)
        review ? @flow.enter!(review) : @workflow.update!(status: :reviewing)
        @workflow.current_stage&.log_run!("rolled_back_to_review")
      end
      true
    end

    # A ci_loop workflow idle in the check or verify stage can skip it, e.g. when bin/ci already ran separately.
    def can_skip_stage?
      @workflow.development? && @workflow.project.ci_loop_ready? && !@workflow.processing? &&
        (@workflow.ci_checking? || @workflow.ci_verifying?)
    end

    # Moves on from the current ci_loop stage to the next one without running it, logging a 'stage_skipped' StageRun.
    # Skipping the check clears its stale output so the verify stage doesn't act on an earlier round's log. Skipping the
    # verify hands the PR to reviewers as a passing verify would (unless local testing comes first).
    def skip_stage!
      return false unless can_skip_stage?

      stage = @workflow.current_stage
      return false unless stage

      testing_locally = @workflow.local_test_before_review?
      verifying = @workflow.ci_verifying?
      @workflow.transaction do
        @flow.complete!(stage, **(verifying ? {} : { ci_output_path: nil, ci_exit_status: nil }))
        stage.log_run!("stage_skipped")
      end
      Stages::ReviewHandoff.new(@workflow, stage).notify_reviewers! if verifying && !testing_locally
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
