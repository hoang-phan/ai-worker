module Stages
  # A runbook stage with `wait_for_workflow` doesn't start until the newest run of that GitHub Actions workflow (started
  # after the previous stage began, so an older deploy can't satisfy it) has finished successfully — like pr_check, it
  # is re-checked every tick and logs once. A finished-but-failed run fails the stage instead of waiting forever.
  class WorkflowRunGate
    Result = Struct.new(:passed, keyword_init: true) do
      def passed? = passed
    end

    def initialize(workflow:, stage:, github:)
      @workflow = workflow
      @stage = stage
      @github = github
    end

    # => Result; logs check_passed / waiting_for_check (once) on the stage. Raises Github::CommandError when the run failed.
    def call
      return Result.new(passed: true) if stage.wait_for_workflow.blank?

      state = github.workflow_run_state(stage.wait_for_workflow, since: since, repo: workflow.variables["REPO"])
      case state[:state]
      when :success
        stage.stage_runs.create!(action: "check_passed", output: state[:url])
        Result.new(passed: true)
      when :failed
        raise Github::CommandError, "GitHub Actions #{stage.wait_for_workflow} finished with #{state[:conclusion]}: #{state[:url]}"
      else
        stage.stage_runs.create!(action: "waiting_for_check", output: state[:url]) unless stage.last_action == "waiting_for_check"
        Result.new(passed: false)
      end
    end

    private

    attr_reader :workflow, :stage, :github

    def since
      previous = workflow.previous_runbook_stage
      previous&.stage_runs&.where(action: "started")&.maximum(:created_at) || workflow.created_at
    end
  end
end
