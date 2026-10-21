require "rails_helper"

RSpec.describe Jira::TimeLogBatch do
  let(:logger) { instance_double(Jira::TimeLogger) }
  let(:workflows) { %w[a b c].map { |name| instance_double(Workflow, label: name) } }
  let(:logs) { workflows.to_h { |workflow| [ workflow, instance_double(TimeLog) ] } }

  subject(:batch) { described_class.new(logger: logger) }

  before do
    workflows.each { |workflow| allow(logger).to receive(:log).with(workflow, 1.5).and_return(logs[workflow]) }
  end

  it "logs every workflow when all succeed" do
    result = batch.call(workflows, 1.5)

    expect(result.logged).to eq(logs.values)
    expect(result.failure).to be_nil
  end

  it "reports the failure when the first workflow fails" do
    allow(logger).to receive(:log).with(workflows[0], 1.5).and_raise(Jira::WorklogError, "a failed")

    result = batch.call(workflows, 1.5)

    expect(result.logged).to eq([])
    expect(result.failure).to eq("a failed")
    expect(logger).not_to have_received(:log).with(workflows[1], anything)
  end

  it "keeps earlier logs and skips later workflows when a middle one fails" do
    allow(logger).to receive(:log).with(workflows[1], 1.5).and_raise(Jira::WorklogError, "b failed")

    result = batch.call(workflows, 1.5)

    expect(result.logged).to eq([ logs[workflows[0]] ])
    expect(result.failure).to eq("b failed")
    expect(logger).not_to have_received(:log).with(workflows[2], anything)
  end
end
