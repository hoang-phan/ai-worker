require "rails_helper"

RSpec.describe Stages::PrReviewFinish, type: :service do
  let_jira_project("pr-review-finish-spec")
  let(:workflow) { build_pr_review_workflow(project, status: :implementing, **running_ai_run) }
  let(:stage) { workflow.stages.find_by!(stage_type: :pr_review) }

  it "resets AI-run state, marks the workflow done and logs review_completed" do
    described_class.new(workflow: workflow, stage: stage).call("agent output")

    expect(workflow.reload).to have_attributes(status: "done").and have_finished_ai_run
    expect(stage_actions(stage)).to eq(%w[review_completed])
    expect(stage.stage_runs.find_by(action: "review_completed").output).to eq "agent output"
  end
end
