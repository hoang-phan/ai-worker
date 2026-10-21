module Stages
  # The success path of a conflict-resolution run: the agent must have left the merge committed (otherwise the merge is
  # aborted and AiCli::CommandError raised); only then does the review-fix prompt run, immediately in the same tick.
  # The agent is never spawned here — start_ai_run is the caller's callable (StartHandler#start_ai_run).
  class ConflictResolutionFinish
    def initialize(workflow:, stage:, project:, git:, prompt:, start_ai_run:)
      @workflow = workflow
      @stage = stage
      @project = project
      @git = git
      @prompt = prompt
      @start_ai_run = start_ai_run
    end

    def call(output)
      if git.merge_in_progress?(project)
        git.abort_merge!(project)
        raise AiCli::CommandError, "#{AiCli::Runner.agent} did not finish resolving merge conflicts with main"
      end

      workflow.update!(Workflow::AI_RUN_RESET)
      stage.log_run!("conflicts_resolved", output: output)
      start_ai_run.call(prompt.body)
    end

    private

    attr_reader :workflow, :stage, :project, :git, :prompt, :start_ai_run
  end
end
