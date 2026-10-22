require "rails_helper"

RSpec.describe SlackPingJob, type: :job do
  it "accepts Sidekiq's execution metadata for legacy raw cron payloads" do
    job = described_class.new
    context = Object.new

    job.jid = "d5bea52e3347544edfd3f5ba"
    job._context = context

    expect(job.jid).to eq("d5bea52e3347544edfd3f5ba")
    expect(job._context).to equal(context)
  end

  it "delegates to the ping collector" do
    collector = instance_double(Slack::PingCollector, collect_all: nil)
    allow(Slack::PingCollector).to receive(:new).and_return(collector)

    described_class.perform_now

    expect(collector).to have_received(:collect_all)
  end
end
