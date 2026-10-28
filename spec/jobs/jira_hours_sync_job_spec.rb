require "rails_helper"

RSpec.describe JiraHoursSyncJob, type: :job do
  let(:io) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(io) }

  it "runs the hours sync and logs failures" do
    sync = instance_double(Jira::HoursSync, call: Jira::HoursSync::Result.new(synced: 1, failed: [ "A-1: boom" ]))

    described_class.perform_now(sync: sync, logger: logger)

    expect(io.string).to match(/A-1: boom/)
  end

  it "swallows an abort such as missing credentials" do
    sync = instance_double(Jira::HoursSync)
    allow(sync).to receive(:call).and_raise(Jira::WorklogError, "not set")

    expect { described_class.perform_now(sync: sync, logger: logger) }.not_to raise_error
    expect(io.string).to include("[JiraHoursSyncJob] not set")
  end

  it "defaults to a real HoursSync" do
    expect { described_class.perform_now(logger: logger) }.not_to raise_error
    expect(io.string).not_to match(/\[JiraHoursSyncJob\]/)
  end
end
