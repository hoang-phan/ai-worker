require "rails_helper"

RSpec.describe Stages::PrCreateFinish, type: :service do
  let(:pr_url) { "https://github.com/acme/widgets/pull/9" }
  let(:github) { double("Github::Client", find_pr_url: pr_url) }
  let(:handoff) { double("Stages::ReviewHandoff", enable_auto_merge!: nil, notify_reviewers!: nil) }
  let(:output) { "agent output" }

  def finish
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
  end

  context "on a ci_loop project" do
    let(:project) { build_ci_project }
    let(:workflow) { build_ci_workflow(project, **running_ai_run) }
    let(:stage) { workflow.stages.find_by!(stage_type: :pr_create) }

    it "discovers the PR, finishes into ci_checking, enables auto-merge, and skips reviewer notification" do
      finish

      expect(github).to have_received(:find_pr_url)
        .with(branch_name: workflow.branch_name, jira_ticket: workflow.jira_ticket, output: output)
      expect(workflow.reload).to have_attributes(
        github_pr_url: pr_url, status: "ci_checking"
      ).and have_finished_ai_run
      expect(stage_actions(stage)).to eq %w[pr_created]
      expect(handoff).to have_received(:enable_auto_merge!).with(pr_url)
      expect(handoff).not_to have_received(:notify_reviewers!)
    end
  end

  context "on a non-ci_loop Jira project" do
    let(:project) { build_jira_project }
    let(:workflow) { build_jira_workflow(project, status: :implementing, **running_ai_run) }
    let(:stage) { build_stage(workflow, :pr_create) }

    it "goes to reviewing, enables auto-merge, and notifies reviewers" do
      finish

      expect(workflow.reload).to have_attributes(
        github_pr_url: pr_url, status: "reviewing"
      ).and have_finished_ai_run
      expect(stage_actions(stage)).to eq %w[pr_created]
      expect(handoff).to have_received(:enable_auto_merge!).with(pr_url)
      expect(handoff).to have_received(:notify_reviewers!)
    end
  end
end
