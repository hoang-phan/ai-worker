require "rails_helper"

RSpec.describe Jira::TimeLogBatch do
  let(:logger) { instance_double(Jira::TimeLogger) }
  let(:workflows) { %w[a b c].map { |name| instance_double(Workflow, label: name) } }
  let(:started_at) { Time.zone.parse("2026-10-21 09:30:00") }
  let(:logs) do
    workflows.each_with_index.to_h do |workflow, index|
      [ workflow, instance_double(TimeLog, ticket_key: "SPEC-#{index + 1}", started_at: started_at + index.hours) ]
    end
  end

  subject(:batch) { described_class.new(logger: logger) }

  before do
    workflows.each { |workflow| allow(logger).to receive(:log).with(workflow, 1.5).and_return(logs[workflow]) }
  end

  it "logs every workflow when all succeed" do
    result = batch.call(workflows, 1.5)

    expect(result.logged).to eq(logs.values)
    expect(result.failure).to be_nil
    expect(result).to be_success
    expect(result.message(1.5)).to eq(
      "Logged 1.5 h on SPEC-1 #{I18n.l(started_at, format: :short)}, " \
      "SPEC-2 #{I18n.l(started_at + 1.hour, format: :short)}, and " \
      "SPEC-3 #{I18n.l(started_at + 2.hours, format: :short)}."
    )
  end

  it "reports the failure when the first workflow fails" do
    allow(logger).to receive(:log).with(workflows[0], 1.5).and_raise(Jira::WorklogError, "a failed")

    result = batch.call(workflows, 1.5)

    expect(result.logged).to eq([])
    expect(result.failure).to eq("a failed")
    expect(result).not_to be_success
    expect(result.message(1.5)).to eq("a failed.")
    expect(logger).not_to have_received(:log).with(workflows[1], anything)
  end

  it "keeps earlier logs and skips later workflows when a middle one fails" do
    allow(logger).to receive(:log).with(workflows[1], 1.5).and_raise(Jira::WorklogError, "b failed")

    result = batch.call(workflows, 1.5)

    expect(result.logged).to eq([ logs[workflows[0]] ])
    expect(result.failure).to eq("b failed")
    expect(result).not_to be_success
    expect(result.message(1.5)).to eq("b failed. Logged before that: SPEC-1 #{I18n.l(started_at, format: :short)}.")
    expect(logger).not_to have_received(:log).with(workflows[2], anything)
  end
end
