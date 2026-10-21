require "rails_helper"

RSpec.describe Stages::PrReviewFinish, type: :service do
  let(:local_directory) { Dir.mktmpdir("pr-review-finish-spec") }
  let(:project) do
    Project.create!(name: "PR review finish #{SecureRandom.hex(4)}", kind: :jira,
                    repo_full_name: "acme/widgets", local_directory: local_directory)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "REV-1", branch_name: "pr-review-finish", github_reviewer: "octocat", status: :implementing,
                              processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log",
                              ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_review, name: "pr_review") }

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "resets AI-run state, marks the workflow done and logs review_completed" do
    described_class.new(workflow: workflow, stage: stage).call("agent output")

    expect(workflow.reload).to have_attributes(status: "done", processing: false, ai_pid: nil, ai_log_path: nil,
                                                ai_started_at: nil, ai_log_offset: 0)
    expect(stage.stage_runs.reorder(:id).pluck(:action)).to eq(%w[review_completed])
    expect(stage.stage_runs.find_by(action: "review_completed").output).to eq "agent output"
  end
end
