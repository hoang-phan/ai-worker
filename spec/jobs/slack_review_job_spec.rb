require "rails_helper"

RSpec.describe SlackReviewJob, type: :job do
  it "runs one cycle for each enabled Jira project" do
    eligible_project = build_jira_project(slack_review_enabled: true)
    build_jira_project(slack_review_enabled: false)
    build_personal_project(slack_review_enabled: true)
    source = instance_double(Slack::ReviewCycleSource)
    prefix = "[SlackReviewJob] project=#{eligible_project.id}"

    expect(Slack::ReviewCycleSource).to receive(:new).with(eligible_project, log_prefix: prefix).and_return(source)
    expect(AgentRuns::SyncCycle).to receive(:call).with(
      source: source,
      log_prefix: prefix
    )

    described_class.perform_now
  end

  it "re-exports the source cadence" do
    expect(described_class::FETCH_EVERY).to eq(Slack::ReviewCycleSource::FETCH_EVERY)
  end

  it "records an expected error and continues to the next project" do
    failing_project = build_jira_project(slack_review_enabled: true)
    next_project = build_jira_project(slack_review_enabled: true)
    failing_source = instance_double(Slack::ReviewCycleSource, poll: nil, persist_failure!: nil, rescue_errors: Slack::ReviewCycleSource::RESCUE_ERRORS)
    next_source = instance_double(Slack::ReviewCycleSource, poll: nil, rescue_errors: Slack::ReviewCycleSource::RESCUE_ERRORS, eligible?: true, idle?: true, due?: true, blockers: [], start!: nil, after_start: nil)

    allow(failing_source).to receive(:poll).and_raise(Slack::FetchError, "slack down")
    allow(failing_source).to receive(:persist_failure!) { |message| failing_project.update!(slack_last_result: message) }
    allow(Slack::ReviewCycleSource).to receive(:new) { |project, **| project == failing_project ? failing_source : next_source }
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(failing_project.reload.slack_last_result).to eq("failed: slack down")
    expect(next_source).to have_received(:start!)
  end
end
