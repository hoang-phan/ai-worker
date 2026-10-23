require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::UatPhase do
  let(:directories) { [] }
  let(:executed) { [] }
  let(:max) { 3 }
  let(:logger) { instance_double(Logger, error: nil) }
  let(:execute) { ->(workflow) { executed << workflow.id } }
  let(:phase) { described_class.new(execute: execute, logger: logger, max_capacity: max) }

  after do
    directories.each { |d| FileUtils.remove_entry(d) if d.start_with?(Dir.tmpdir) && File.exist?(d) }
  end

  def workflow(status:, position: 1, **attrs)
    directory = Dir.mktmpdir("uat-phase-spec")
    directories << directory
    project = build_jira_project(local_directory: directory)
    build_jira_workflow(project, status: status, kind: :development, position: position, **attrs)
  end

  context "with no free slots" do
    let(:max) { 1 }

    it "does nothing" do
      workflow(status: :implementing, processing: true)
      due = workflow(status: :uat_waiting, uat_test_at: 1.minute.ago)

      phase.call

      expect(executed).to be_empty
      expect(due.reload).to be_uat_waiting
    end
  end

  it "moves due uat_waiting workflows to uat_testing and executes them" do
    due = workflow(status: :uat_waiting, uat_test_at: 1.minute.ago, position: 1)
    not_due = workflow(status: :uat_waiting, uat_test_at: 1.hour.from_now, position: 2)

    phase.call

    expect(executed).to eq([ due.id ])
    expect(due.reload).to be_uat_testing
    expect(not_due.reload).to be_uat_waiting
  end

  it "retries idle uat_testing workflows" do
    retrying = workflow(status: :uat_testing)

    phase.call

    expect(executed).to eq([ retrying.id ])
    expect(retrying.reload).to be_uat_testing
  end

  context "when only one slot is free" do
    let(:max) { 2 }

    it "executes only the earliest due workflow" do
      workflow(status: :implementing, processing: true)
      first = workflow(status: :uat_waiting, uat_test_at: 2.minutes.ago, position: 1)
      second = workflow(status: :uat_waiting, uat_test_at: 1.minute.ago, position: 2)

      phase.call

      expect(executed).to eq([ first.id ])
      expect(second.reload).to be_uat_waiting
    end
  end

  it "logs an executor failure and continues" do
    failed = workflow(status: :uat_waiting, uat_test_at: 2.minutes.ago, position: 1)
    following = workflow(status: :uat_waiting, uat_test_at: 1.minute.ago, position: 2)
    calls = []
    flaky = lambda do |wf|
      calls << wf.id
      raise "boom" if wf.id == failed.id
    end

    described_class.new(execute: flaky, logger: logger, max_capacity: max).call

    expect(calls).to eq([ failed.id, following.id ])
    expect(logger).to have_received(:error).with("[scheduler] workflow=#{failed.id} RuntimeError: boom")
  end
end
