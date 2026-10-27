require "rails_helper"

RSpec.describe Stages::PrCheckRun, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "PRC-1", branch_name: "pr-check-run", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing)
  end
  let(:stage) { build_stage(workflow, :pr_check) }
  let(:github) { double("Github::Client", merged?: false, review_decision: "CHANGES_REQUESTED", checks_failing?: false) }
  let(:git) { double("Git::BranchService", update_with_main!: :updated) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:handoff) { double("Stages::ReviewHandoff", reviewers: [ "octocat" ]) }
  let(:launcher) { spy("launcher") }

  def run
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git,
                        handoff: handoff, prompt: prompt, launcher: launcher).call
  end

  it "marks a merged PR merged without inspecting reviews" do
    allow(github).to receive(:merged?).and_return(true)
    allow(github).to receive(:review_decision)
    run

    expect(workflow.reload.status).to eq "merged"
    expect(stage_actions(stage)).to eq %w[pr_merged_closed]
    expect(github).not_to have_received(:review_decision)
    expect(launcher).not_to have_received(:call)
  end

  it "closes an approved PR as done" do
    allow(github).to receive(:review_decision).and_return("APPROVED")
    run

    expect(workflow.reload.status).to eq "done"
    expect(stage_actions(stage)).to eq %w[approved_closed]
    expect(launcher).not_to have_received(:call)
    expect(github).to have_received(:review_decision).with(workflow.github_pr_url, [ "octocat" ])
  end

  it "starts the review-fix run when changes are requested and main merges cleanly" do
    run

    expect(git).to have_received(:update_with_main!).with(project, "pr-check-run")
    expect(launcher).to have_received(:call).with("the prompt")
    expect(stage_actions(stage)).to be_empty
    expect(github).to have_received(:review_decision).with(workflow.github_pr_url, [ "octocat" ])
    expect(github).not_to have_received(:checks_failing?)
  end

  it "starts conflict resolution when main conflicts" do
    allow(git).to receive(:update_with_main!).and_return(:conflict)
    run

    expect(launcher).to have_received(:call).with(Prompts::StagePrompt::CONFLICT, action: "conflict_resolution_started")
    expect(launcher).not_to have_received(:call).with("the prompt")
    expect(github).not_to have_received(:checks_failing?)
  end

  it "logs local_test_failing then starts the fix run when changes are requested" do
    workflow.update!(local_test_feedback: "Login button is broken")
    run

    expect(stage_actions(stage)).to eq %w[local_test_failing]
    expect(launcher).to have_received(:call).with("the prompt")
    expect(github).not_to have_received(:checks_failing?)
  end

  it "logs local_test_failing then starts conflict resolution when main conflicts" do
    workflow.update!(local_test_feedback: "Login button is broken")
    allow(git).to receive(:update_with_main!).and_return(:conflict)
    run

    expect(stage_actions(stage)).to eq %w[local_test_failing]
    expect(launcher).to have_received(:call).with(Prompts::StagePrompt::CONFLICT, action: "conflict_resolution_started")
    expect(github).not_to have_received(:checks_failing?)
  end

  it "logs no_action_pending when the review decision is nil" do
    allow(github).to receive(:review_decision).and_return(nil)
    run

    expect(stage_actions(stage)).to eq %w[no_action_pending]
    expect(launcher).not_to have_received(:call)
    expect(github).to have_received(:review_decision).with(workflow.github_pr_url, [ "octocat" ])
  end

  it "logs checks_failing then starts the fix run when approved but checks fail" do
    allow(github).to receive(:review_decision).and_return("APPROVED")
    allow(github).to receive(:checks_failing?).and_return(true)
    run

    expect(stage_actions(stage)).to eq %w[checks_failing]
    expect(launcher).to have_received(:call).with("the prompt")
    expect(github).to have_received(:review_decision).with(workflow.github_pr_url, [ "octocat" ])
    expect(github).to have_received(:checks_failing?).with(workflow.github_pr_url)
  end

  it "propagates a git error without starting the agent" do
    allow(git).to receive(:update_with_main!).and_raise(Git::CommandError, "nope")

    expect { run }.to raise_error(Git::CommandError, "nope")
    expect(launcher).not_to have_received(:call)
  end
end
