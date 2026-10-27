require "rails_helper"

RSpec.describe JiraHoursSyncJob, type: :job do
  before { allow(Rails.logger).to receive(:warn) }

  it "runs the hours sync and logs failures" do
    sync = instance_double(Jira::HoursSync, call: Jira::HoursSync::Result.new(synced: 1, failed: [ "A-1: boom" ]))

    described_class.perform_now(sync: sync)

    expect(Rails.logger).to have_received(:warn).with(/A-1: boom/)
  end

  it "swallows an abort such as missing credentials" do
    sync = instance_double(Jira::HoursSync)
    allow(sync).to receive(:call).and_raise(Jira::WorklogError, "not set")

    expect { described_class.perform_now(sync: sync) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with("[JiraHoursSyncJob] not set")
  end

  it "defaults to a real HoursSync" do
    expect { described_class.perform_now }.not_to raise_error
    expect(Rails.logger).not_to have_received(:warn)
  end
end
