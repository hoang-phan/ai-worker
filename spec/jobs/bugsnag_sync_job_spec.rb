require "rails_helper"

RSpec.describe BugsnagSyncJob, type: :job do
  it "runs one cycle for every Bugsnag sync with its exact wiring" do
    first_sync = build_jira_project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "WEB")
    second_sync = build_personal_project.bugsnag_syncs.create!(bugsnag_project: "api", jira_project: "API", auto_sync: false)
    first_source = instance_double(Bugsnag::SyncCycleSource)
    second_source = instance_double(Bugsnag::SyncCycleSource)

    expect(Bugsnag::SyncCycleSource).to receive(:new).with(first_sync).and_return(first_source)
    expect(Bugsnag::SyncCycleSource).to receive(:new).with(second_sync).and_return(second_source)
    expect(AgentRuns::SyncCycle).to receive(:call).with(
      source: first_source,
      log_prefix: "[BugsnagSyncJob] bugsnag_sync=#{first_sync.id}"
    )
    expect(AgentRuns::SyncCycle).to receive(:call).with(
      source: second_source,
      log_prefix: "[BugsnagSyncJob] bugsnag_sync=#{second_sync.id}"
    )

    described_class.perform_now
  end

  it "re-exports the source run hour" do
    expect(described_class::RUN_HOUR).to eq(Bugsnag::SyncCycleSource::RUN_HOUR)
  end

  it "records an expected error and continues to the next sync" do
    project = build_jira_project
    failing_sync = project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "WEB")
    next_sync = project.bugsnag_syncs.create!(bugsnag_project: "api", jira_project: "API")
    failing_source = instance_double(Bugsnag::SyncCycleSource, poll: nil, persist_failure!: nil, rescue_errors: Bugsnag::SyncCycleSource::RESCUE_ERRORS)
    next_source = instance_double(Bugsnag::SyncCycleSource, poll: nil, rescue_errors: Bugsnag::SyncCycleSource::RESCUE_ERRORS, eligible?: true, idle?: true, due?: true, blockers: [], start!: nil, after_start: nil)

    allow(failing_source).to receive(:poll).and_raise(Bugsnag::FetchError, "no result")
    allow(failing_source).to receive(:persist_failure!) { |message| failing_sync.update!(last_result: message) }
    allow(Bugsnag::SyncCycleSource).to receive(:new) { |sync| sync == failing_sync ? failing_source : next_source }
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(failing_sync.reload.last_result).to eq("failed: no result")
    expect(next_source).to have_received(:start!)
  end
end
