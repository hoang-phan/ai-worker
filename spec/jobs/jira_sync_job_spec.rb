require "rails_helper"

RSpec.describe JiraSyncJob, type: :job do
  it "runs one Jira cycle per Jira sync with a configured Jira URL" do
    eligible_project = build_jira_project(jira_base_url: "https://acme.atlassian.net")
    eligible_sync = eligible_project.jira_syncs.create!
    build_jira_project(jira_base_url: nil).jira_syncs.create!
    build_personal_project.jira_syncs.create!
    source = instance_double(Jira::SyncCycleSource)
    prefix = "[JiraSyncJob] jira_sync=#{eligible_sync.id}"

    expect(Jira::SyncCycleSource).to receive(:new).with(eligible_sync, log_prefix: prefix).and_return(source)
    expect(AgentRuns::SyncCycle).to receive(:call).with(
      source: source,
      log_prefix: prefix
    )

    described_class.perform_now
  end

  it "re-exports the source cadence" do
    expect(described_class::FETCH_EVERY).to eq(Jira::SyncCycleSource::FETCH_EVERY)
  end

  it "records an expected error and continues to the next sync" do
    project = build_jira_project(jira_base_url: "https://acme.atlassian.net")
    failing_sync = project.jira_syncs.create!
    next_sync = project.jira_syncs.create!
    failing_source = instance_double(Jira::SyncCycleSource, poll: nil, persist_failure!: nil, rescue_errors: Jira::SyncCycleSource::RESCUE_ERRORS)
    next_source = instance_double(Jira::SyncCycleSource, poll: nil, rescue_errors: Jira::SyncCycleSource::RESCUE_ERRORS, eligible?: true, idle?: true, due?: true, blockers: [], start!: nil, after_start: nil)

    allow(failing_source).to receive(:poll).and_raise(Jira::FetchError, "bad json")
    allow(failing_source).to receive(:persist_failure!) { |message| failing_sync.update!(last_result: message) }
    allow(Jira::SyncCycleSource).to receive(:new) { |sync, **| sync == failing_sync ? failing_source : next_source }
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(failing_sync.reload.last_result).to eq("failed: bad json")
    expect(next_source).to have_received(:start!)
  end
end
