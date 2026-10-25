require "rails_helper"

RSpec.describe Stages::ImplementationFinish, type: :service do
  let_jira_project("implementation-finish-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "DONE-1", branch_name: "implementation-finish", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing, **running_ai_run)
  end
  let(:stage) { build_stage(workflow, :implementation) }
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
      github_pr_url: "https://github.com/acme/widgets/pull/9", status: "reviewing"
    ).and have_finished_ai_run
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
