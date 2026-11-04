module Workflows
  # The stage-by-stage execution of a non-runbook workflow. The stage to run is `current_stage_id`; the workflow's status
  # is only the label of that stage (STATUS_BY_STAGE_TYPE), kept for the scheduler's queries and the badges.
  #
  # A stage ends one of three ways: completed (go to the next stage of the pipeline, or `done` after the last),
  # failed (an expected negative result, e.g. the reviewer requested changes or the checks failed: go to the stage's
  # failure target, see #failure_target), or in error (a broken run: the same stage is retried, see Stages::FailureHandler).
  # Post-merge work (`merged` -> jira_update, `uat_*` -> uat_test) is not part of the pipeline and stays status-driven.
  class StageFlow
    # The pipeline's stage types in the order they run. A workflow has at most one stage of each type, and only some of
    # them (a standard workflow: implementation, [local_test], pr_check; ci_loop: simple_implementation, pr_create,
    # ci_check, ci_verify, [local_test], pr_check; personal: task; PR review: pr_review).
    PIPELINE_ORDER = %w[implementation simple_implementation task pr_review pr_create ci_check ci_verify local_test pr_check].freeze

    # The status a workflow shows while it is on a stage of each type.
    STATUS_BY_STAGE_TYPE = {
      "implementation" => :implementing, "simple_implementation" => :implementing, "task" => :implementing,
      "pr_review" => :implementing, "pr_create" => :opening_pr, "ci_check" => :ci_checking, "ci_verify" => :ci_verifying,
      "local_test" => :local_testing, "pr_check" => :reviewing
    }.freeze

    # Stage types that can end "failed" -> the type of the stage they go back to unless one was selected on the stage.
    DEFAULT_FAILURE_TYPE = { "pr_check" => "pr_check", "ci_verify" => "ci_check", "local_test" => "pr_check" }.freeze

    # A stage routed back this many times (since the last `resumed`) parks the workflow as errored instead of looping.
    MAX_FAILURE_ROUNDS = 10

    def self.pipeline_type?(stage_type) = PIPELINE_ORDER.include?(stage_type.to_s)

    def self.failure_capable?(stage_type) = DEFAULT_FAILURE_TYPE.key?(stage_type.to_s)

    def initialize(workflow)
      @workflow = workflow
    end

    # The workflow's runnable pipeline stages in running order. local_test only counts while the project can still run it.
    def pipeline
      @workflow.stages.to_a
               .select { |stage| self.class.pipeline_type?(stage.stage_type) && runnable?(stage) }
               .sort_by { |stage| PIPELINE_ORDER.index(stage.stage_type) }
    end

    def first_stage = pipeline.first

    # The pipeline stage after `stage`, nil after the last one.
    def stage_after(stage)
      rank = PIPELINE_ORDER.index(stage.stage_type)
      return nil unless rank

      pipeline.find { |candidate| PIPELINE_ORDER.index(candidate.stage_type) > rank }
    end

    # Where a failed `stage` goes: the stage selected on it, else its type's default, else itself (a retry). Never a
    # stage outside the pipeline, so a stale selection can't strand the workflow.
    def failure_target(stage)
      stages = pipeline
      stages.find { |candidate| candidate.id == stage.failure_stage_id } || default_failure_target(stage)
    end

    # The type's default failure target (the stage itself when its type has none or the workflow lacks that stage).
    def default_failure_target(stage)
      default_type = DEFAULT_FAILURE_TYPE[stage.stage_type]
      pipeline.find { |candidate| candidate.stage_type == default_type } || stage
    end

    def status_for(stage) = STATUS_BY_STAGE_TYPE.fetch(stage.stage_type)

    # Puts the workflow on `stage` (with its status), ends any agent run (Workflow::AI_RUN_RESET) and applies `attrs`
    # in the same update.
    def enter!(stage, **attrs)
      @workflow.update!(Workflow::AI_RUN_RESET.merge(attrs).merge(current_stage_id: stage.id, status: status_for(stage)))
      stage
    end

    # `stage` ended successfully: on to the next stage, or `done` when it was the last. Returns the next stage or nil.
    def complete!(stage, **attrs)
      following = stage_after(stage)
      return enter!(following, **attrs) if following

      @workflow.update!(Workflow::AI_RUN_RESET.merge(attrs).merge(status: :done))
      nil
    end

    # `stage` ended with its expected negative result: back to its failure target, logging the route. Once the stage has
    # been routed back MAX_FAILURE_ROUNDS times the workflow is parked errored instead (a person resumes it).
    # Returns the target, or nil when the loop was cut.
    def route_failed!(stage, **attrs)
      if stage.routed_failure_rounds >= MAX_FAILURE_ROUNDS
        @workflow.update!(Workflow::AI_RUN_RESET.merge(attrs).merge(status: :errored))
        stage.log_run!("failure_rounds_exhausted")
        return nil
      end

      target = failure_target(stage)
      enter!(target, **attrs)
      stage.log_run!("failure_routed", output: "back to #{target.display_name}")
      target
    end

    private

    def runnable?(stage)
      stage.stage_type != "local_test" || @workflow.project.local_test_ready?
    end
  end
end
