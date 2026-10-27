require "rails_helper"

RSpec.describe Stages::FailureHandler, type: :service do
  let_jira_project("failure-handler-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "FAIL-1", branch_name: "failure-handler", status: :implementing, auto_run: true, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :implementation) }
  let(:error) { AiCli::CommandError.new("boom") }
  let(:threshold) { 3 }

  def handle
    described_class.new(workflow: workflow, stage: stage, project: project, error: error, threshold: threshold, git: git).call
  end

  let(:git) { class_double(Git::BranchService, abort_merge!: nil) }

  it "clears the AI-run fields, stops auto-run and logs the failure" do
    handle

    workflow.reload
    expect(workflow).to have_attributes(auto_run: false, status: "implementing").and have_finished_ai_run
    expect(stage.stage_runs.where(action: "failed").sole).to have_attributes(error: "boom")
    expect(git).not_to have_received(:abort_merge!)
  end

  it "aborts an in-progress merge when the stage was resolving conflicts" do
    stage.stage_runs.create!(action: "conflict_resolution_started")

    handle

    expect(git).to have_received(:abort_merge!).with(project)
    expect(stage.stage_runs.pluck(:action)).to include("failed")
  end

  it "keeps the workflow retryable below the threshold" do
    1.times { stage.stage_runs.create!(action: "failed") }

    handle

    expect(workflow.reload.status).to eq("implementing")
  end

  it "parks the workflow as errored at the threshold" do
    2.times { stage.stage_runs.create!(action: "failed") }
    stage.stage_runs.create!(action: "started")

    expect { handle }.to change { workflow.reload.status }.from("implementing").to("errored")
    expect(workflow.processing).to be(false)
  end
end
