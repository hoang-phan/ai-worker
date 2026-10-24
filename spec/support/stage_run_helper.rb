module StageRunHelper
  def stage_actions(stage)
    stage.stage_runs.reorder(:id).pluck(:action)
  end
end

RSpec::Matchers.define :have_finished_ai_run do
  match do |workflow|
    @attributes_matcher = have_attributes(Workflow::AI_RUN_RESET)
    @attributes_matcher.matches?(workflow)
  end

  failure_message do
    @attributes_matcher.failure_message
  end
end

RSpec.configure do |config|
  config.include StageRunHelper
end
