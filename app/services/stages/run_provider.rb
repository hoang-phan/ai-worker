module Stages
  # Which agent CLI a workflow's runs use. Precedence: the workflow's round-robin provider (AiCli::Rotation, pinned per
  # workflow), then the app-wide AiCli::AgentSetting (applied by AiCli::Runner when `override` is nil).
  class RunProvider
    def initialize(workflow:, rotation: AiCli::Rotation)
      @workflow = workflow
      @rotation = rotation
    end

    # What the runner is told and `ai_provider` stores; nil means the app-wide agent.
    # The agent CLI this workflow runs with. Precedence: the rotation provider picked by AiCli::Rotation the first time
    # one is needed (pinned per workflow for its life); else nil, meaning the app-wide AiCli::AgentSetting applies.
    def override
      return workflow.rotation_provider if workflow.rotation_provider.present?

      provider = rotation.next_provider
      workflow.update_column(:rotation_provider, provider) if provider
      provider
    end

    private

    attr_reader :workflow, :rotation
  end
end
