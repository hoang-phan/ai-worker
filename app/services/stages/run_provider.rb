module Stages
  # Which agent CLI a stage's run uses. Precedence: the stage agent's own provider, then the workflow's round-robin
  # provider (AiCli::Rotation, pinned per workflow), then the app-wide AiCli::AgentSetting.
  class RunProvider
    def initialize(workflow:, stage:)
      @workflow = workflow
      @stage = stage
    end

    # What the runner is told and `ai_provider` stores; nil means the app-wide agent.
    def override
      stage.agent&.provider.presence || workflow.rotation_provider!
    end

    def name
      override || AiCli::AgentSetting.current
    end

    def provider
      AiCli::Providers.find(name)
    end

    private

    attr_reader :workflow, :stage
  end
end
