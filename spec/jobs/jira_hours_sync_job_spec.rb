require "rails_helper"

RSpec.describe JiraHoursSyncJob, type: :job do
  before { allow(Rails.logger).to receive(:warn) }

  it "runs the hours sync and logs failures" do
    sync = instance_double(Jira::HoursSync, call: Jira::HoursSync::Result.new(synced: 1, failed: [ "A-1: boom" ]))
    allow(Jira::HoursSync).to receive(:new).and_return(sync)

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with(/A-1: boom/)
  end

  it "swallows an abort such as missing credentials" do
    allow(Jira::HoursSync).to receive(:new).and_return(instance_double(Jira::HoursSync).tap { |s| allow(s).to receive(:call).and_raise(Jira::WorklogError, "not set") })

    expect { described_class.perform_now }.not_to raise_error
  end
end
