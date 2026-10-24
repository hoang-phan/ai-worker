module Prompts
  # Builds the text the agent CLI is run with for one stage of a workflow.
  class StagePrompt
    CONFLICT = Prompts::ConflictResolution::TEXT

    def initialize(workflow, stage, notifier: nil, latest_log: Prompts::StageSectionList::DEFAULT_LATEST_LOG)
      @workflow = workflow
      @stage = stage
      @section_list = Prompts::StageSectionList.new(workflow: workflow, stage: stage, notifier: notifier, latest_log: latest_log)
    end

    def body
      text = stage.prompt.presence || stage.effective_template&.body || Prompts::Defaults.for(stage.stage_type)
      raise ArgumentError, "no prompt available for stage #{stage.id}" unless text

      Prompts::Renderer.render(text, workflow) + section_list.to_s
    end

    # Wraps `message` in the instructions for posting it to the stage's Slack channel.
    def slack_message(message)
      Prompts::SlackPost.new(channel: Prompts::Renderer.render(stage.channel.to_s, workflow), message: message).to_s
    end

    private

    attr_reader :workflow, :stage, :section_list
  end
end
