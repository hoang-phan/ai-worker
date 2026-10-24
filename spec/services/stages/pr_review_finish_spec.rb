require "rails_helper"

RSpec.describe Stages::PrReviewFinish, type: :service do
  let_tmpdir(:local_directory, "pr-review-finish-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "REV-1", branch_name: "pr-review-finish", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_review, name: "pr_review") }

  it "resets AI-run state, marks the workflow done and logs review_completed" do
    described_class.new(workflow: workflow, stage: stage).call("agent output")

    expect(workflow.reload).to have_attributes(status: "done", processing: false, ai_pid: nil, ai_log_path: nil,
                                                ai_started_at: nil, ai_log_offset: 0)
    expect(stage.stage_runs.reorder(:id).pluck(:action)).to eq(%w[review_completed])
    expect(stage.stage_runs.find_by(action: "review_completed").output).to eq "agent output"
  end
end
