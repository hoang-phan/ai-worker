require "rails_helper"

RSpec.describe SlackPingJob, type: :job do
  it "delegates to the ping collector" do
    collector = instance_double(Slack::PingCollector, collect_all: nil)
    allow(Slack::PingCollector).to receive(:new).and_return(collector)

    described_class.perform_now

    expect(collector).to have_received(:collect_all)
  end
end
