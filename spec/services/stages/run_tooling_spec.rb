require "rails_helper"

RSpec.describe Stages::RunTooling, type: :service do
  Stage.stage_types.each_key do |type|
    if type == "ci_check"
      it "uses the plain command runner and poller for #{type}" do
        tooling = described_class.for(Stage.new(stage_type: type))

        expect(tooling).to have_attributes(runner: Ci::CommandRunner, poller_class: Ci::CheckPoller)
      end
    else
      it "uses the agent CLI runner and poller for #{type}" do
        tooling = described_class.for(Stage.new(stage_type: type))

        expect(tooling).to have_attributes(runner: AiCli::Runner, poller_class: AiCli::RunPoller)
      end
    end
  end
end
