module Stages
  # The success path of a pr_review stage: mark the workflow done and log the review.
  class PrReviewFinish
    def initialize(workflow:, stage:)
      @workflow = workflow
      @stage = stage
    end

    def call(output)
      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :done))
      stage.log_run!("review_completed", output: output)
    end

    private

    attr_reader :workflow, :stage
  end
end
