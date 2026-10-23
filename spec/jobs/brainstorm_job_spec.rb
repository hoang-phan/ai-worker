require "rails_helper"

RSpec.describe BrainstormJob, type: :job do
  it "runs one cycle for each enabled personal project" do
    eligible_project = build_personal_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery")
    build_personal_project(brainstorm_enabled: false, brainstorm_goal: "Improve delivery")
    build_jira_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery")
    source = instance_double(Brainstorm::CycleSource)
    prefix = "[BrainstormJob] project=#{eligible_project.id}"

    expect(Brainstorm::CycleSource).to receive(:new).with(eligible_project).and_return(source)
    expect(AgentRuns::SyncCycle).to receive(:call).with(
      source: source,
      log_prefix: prefix,
      rescue_errors: [ Brainstorm::FetchError, AiCli::CommandError ]
    )

    described_class.perform_now
  end

  it "records an expected error and continues to the next project" do
    failing_project = build_personal_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery")
    next_project = build_personal_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery")
    failing_source = instance_double(Brainstorm::CycleSource, poll: nil, persist_failure!: nil)
    next_source = instance_double(Brainstorm::CycleSource, poll: nil, eligible?: true, idle?: true, due?: true, blockers: [], start!: nil, after_start: nil)

    allow(failing_source).to receive(:poll).and_raise(Brainstorm::FetchError, "no result")
    allow(failing_source).to receive(:persist_failure!) { |message| failing_project.update!(brainstorm_last_result: message) }
    allow(Brainstorm::CycleSource).to receive(:new) { |project| project == failing_project ? failing_source : next_source }
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(failing_project.reload.brainstorm_last_result).to eq("failed: no result")
    expect(next_source).to have_received(:start!)
  end
end
