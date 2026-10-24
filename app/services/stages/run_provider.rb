module Stages
  # Which agent CLI a workflow's runs use. Precedence: the workflow's round-robin provider (AiCli::Rotation, pinned per
  # workflow), then the app-wide AiCli::AgentSetting (applied by AiCli::Runner when `override` is nil).
  class RunProvider
    def initialize(workflow:)
      @workflow = workflow
    end

    # What the runner is told and `ai_provider` stores; nil means the app-wide agent.
    def override
      workflow.rotation_provider!
    end

    private

    attr_reader :workflow
  end
end
