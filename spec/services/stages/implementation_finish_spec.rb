require "rails_helper"

RSpec.describe Stages::ImplementationFinish, type: :service do
  let_tmpdir(:local_directory, "implementation-finish-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "DONE-1", branch_name: "implementation-finish", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing,
                                 processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log",
                                 ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage) { workflow.stages.create!(stage_type: :implementation, name: "implementation") }
  let(:github) { double("Github::Client", find_pr_url: "https://github.com/acme/widgets/pull/9") }
  let(:handoff) { double("Stages::ReviewHandoff", enable_auto_merge!: nil, notify_reviewers!: nil) }
  let(:output) { "agent output" }

  def finish(out = output)
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(out)
  end

  it "discovers the PR, clears the AI run, starts review, and hands off" do
    allow(project).to receive(:local_test_ready?).and_return(false)

    finish

    expect(github).to have_received(:find_pr_url).with(branch_name: "implementation-finish", jira_ticket: "DONE-1", output: output)
    expect(workflow.reload).to have_attributes(
      github_pr_url: "https://github.com/acme/widgets/pull/9", status: "reviewing",
      processing: false, ai_pid: nil, ai_log_path: nil, ai_started_at: nil, ai_log_offset: 0
    )
    expect(stage.stage_runs.pluck(:action)).to eq([ "ran_implementation" ])
    expect(handoff).to have_received(:enable_auto_merge!).with("https://github.com/acme/widgets/pull/9")
    expect(handoff).to have_received(:notify_reviewers!).with(no_args)
  end

  it "waits for the local test before auto-merge or reviewer notification on development workflows" do
    allow(project).to receive(:local_test_ready?).and_return(true)
    allow(workflow).to receive(:development?).and_return(true)

    finish

    expect(workflow.reload.status).to eq "local_testing"
    expect(handoff).not_to have_received(:enable_auto_merge!)
    expect(handoff).not_to have_received(:notify_reviewers!)
  end
end
