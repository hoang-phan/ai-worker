require "rails_helper"

RSpec.describe Stages::MergeCheck, type: :service do
  let(:project) do
    Project.create!(name: "Merge check #{SecureRandom.hex(4)}", kind: :jira,
                    repo_full_name: "acme/widgets", local_directory: Dir.tmpdir)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "MC-1", branch_name: "merge-check", github_reviewer: "octocat",
                              github_pr_url: "https://github.com/acme/widgets/pull/1", status: :done)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_check, name: "pr_check") }
  let(:github) { double("Github::Client", merged?: false) }

  def call = described_class.new(workflow: workflow, stage: stage, github: github).call

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  it "marks the workflow merged and logs pr_merged_detected when the PR is merged" do
    allow(github).to receive(:merged?).with(workflow.github_pr_url).and_return(true)

    call

    expect(workflow.reload).to be_merged
    expect(actions).to eq([ "pr_merged_detected" ])
  end

  it "does nothing when the PR is not merged" do
    call

    expect(workflow.reload).to be_done
    expect(actions).to be_empty
  end

  it "logs merge_check_failed with the message and does not raise on Github::CommandError" do
    allow(github).to receive(:merged?).and_raise(Github::CommandError, "gh exploded")

    expect { call }.not_to raise_error

    expect(workflow.reload).to be_done
    expect(actions).to eq([ "merge_check_failed" ])
    expect(stage.stage_runs.last.error).to eq("gh exploded")
  end
end
