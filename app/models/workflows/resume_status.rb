module Workflows
  # Where an errored workflow goes back to.
  class ResumeStatus
    # status: the in-flight status to resume in; stage: the pipeline stage to put the workflow on (nil: leave
    # current_stage_id alone); origin: the stage that errored, when known.
    Target = Struct.new(:status, :stage, :origin, keyword_init: true)

    def initialize(workflow, flow: Workflows::StageFlow.new(workflow))
      @workflow = workflow
      @flow = flow
    end

    # A scheduled UAT test resumes the UAT test. A runbook resumes at its stored stage. Otherwise the workflow goes back
    # to the stage that errored (the one it was on, else the newest with a run, else review once a PR exists, else the
    # first), except that an exhausted CI loop restarts at the verify stage's failure target (the check) with a fresh budget.
    def call
      return Target.new(status: :uat_testing) if @workflow.uat_test_at.present?
      return Target.new(status: :implementing) if @workflow.runbook?

      origin = errored_stage
      return Target.new(status: :implementing) unless origin

      stage = origin.last_action == "ci_rounds_exhausted" ? @flow.failure_target(origin) : origin
      Target.new(status: @flow.status_for(stage), stage: stage, origin: origin)
    end

    private

    def errored_stage
      pipeline = @flow.pipeline
      stored = pipeline.find { |stage| stage.id == @workflow.current_stage_id }
      return stored if stored

      from_runs(pipeline) || (pull_request_stage(pipeline) if @workflow.development? && @workflow.github_pr_url.present?) || pipeline.first
    end

    def from_runs(pipeline)
      run = StageRun.where(stage_id: pipeline.map(&:id)).where.not(action: "resumed").order(:id).last
      run && pipeline.find { |stage| stage.id == run.stage_id }
    end

    def pull_request_stage(pipeline) = pipeline.find { |stage| stage.stage_type == "pr_check" }
  end
end
