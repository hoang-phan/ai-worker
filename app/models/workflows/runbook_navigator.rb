module Workflows
  # The runbook state machine: starting at the first stage, stepping with Next, and finding the neighbouring stages.
  class RunbookNavigator
    def initialize(workflow)
      @workflow = workflow
    end

    # Starts a runbook at its first stage (a runbook with no stages is just done).
    def start!
      first = @workflow.stages.first
      return @workflow.update!(status: :done) unless first

      @workflow.update!(status: :implementing, current_stage_id: first.id, awaiting_next: false, auto_run: false)
    end

    # The Next button (and a stage's `auto_advance`): close out the finished stage and move to the following one,
    # or finish the workflow after the last stage. The scheduler then starts the following stage by itself
    # (`auto_run`) — it stops again only at a stage without `auto_advance`, at a failure, or at the end.
    def advance!
      raise ArgumentError, "workflow is not waiting for Next" unless @workflow.runbook? && @workflow.awaiting_next?

      finished = @workflow.current_stage
      following = next_stage
      finished&.stage_runs&.create!(action: "advanced")
      if following
        @workflow.update!(current_stage_id: following.id, status: :implementing, awaiting_next: false, auto_run: true)
      else
        @workflow.update!(status: :done, awaiting_next: false, auto_run: false)
      end
    end

    def next_stage
      list = @workflow.stages.to_a
      index = current_index(list)
      index ? list[index + 1] : list.first
    end

    def previous_stage
      list = @workflow.stages.to_a
      index = current_index(list)
      index&.positive? ? list[index - 1] : nil
    end

    private

    def current_index(list)
      list.index { |stage| stage.id == @workflow.current_stage_id }
    end
  end
end
