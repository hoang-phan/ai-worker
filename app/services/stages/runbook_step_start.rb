module Stages
  # Runbook stages are plain agent runs: `agent` runs the prompt as written,
  # `message` has the agent post the rendered text to Slack via its MCP connector.
  # Either way the workflow then waits for a person to click Next (finish_runbook_step).
  class RunbookStepStart
    def initialize(workflow:, stage:, github:, prompt:, launcher:)
      @workflow = workflow
      @stage = stage
      @github = github
      @prompt = prompt
      @launcher = launcher
    end

    def call
      return unless Stages::WorkflowRunGate.new(workflow: workflow, stage: stage, github: github).call.passed?

      launcher.call(stage.run_message? ? prompt.slack_message(prompt.body) : prompt.body)
    end

    private

    attr_reader :workflow, :stage, :github, :prompt, :launcher
  end
end
