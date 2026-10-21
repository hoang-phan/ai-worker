module Stages
  # A `done` workflow whose PR has since been merged becomes `merged`. Called by the scheduler only on idle ticks.
  # A failed lookup is logged and retried next idle tick — it never fails the workflow or raises.
  class MergeCheck
    def initialize(workflow:, stage:, github:)
      @workflow = workflow
      @stage = stage
      @github = github
    end

    def call
      return unless github.merged?(workflow.github_pr_url)

      workflow.update!(status: :merged)
      stage.log_run!("pr_merged_detected")
    rescue Github::CommandError => e
      stage.log_run!("merge_check_failed", error: e.message)
    end

    private

    attr_reader :workflow, :stage, :github
  end
end
