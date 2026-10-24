require "rails_helper"

RSpec.describe Stages::PrReviewFinish, type: :service do
  let_jira_project("pr-review-finish-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "REV-1", branch_name: "pr-review-finish", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_review, name: "pr_review") }

  it "resets AI-run state, marks the workflow done and logs review_completed" do
    described_class.new(workflow: workflow, stage: stage).call("agent output")

    expect(workflow.reload).to have_attributes(status: "done").and have_finished_ai_run
    expect(stage_actions(stage)).to eq(%w[review_completed])
    expect(stage.stage_runs.find_by(action: "review_completed").output).to eq "agent output"
  end
end
