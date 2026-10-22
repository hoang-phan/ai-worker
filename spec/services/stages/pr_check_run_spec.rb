require "rails_helper"

RSpec.describe Stages::PrCheckRun, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "PRC-1", branch_name: "pr-check-run", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_check, name: "pr_check") }
  let(:github) { double("Github::Client", merged?: false, review_decision: "CHANGES_REQUESTED", checks_failing?: false) }
  let(:git) { double("Git::BranchService", update_with_main!: :updated) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:handoff) { double("Stages::ReviewHandoff", reviewers: [ "octocat" ]) }
  let(:start_ai_run) { spy("start_ai_run") }
  let(:decision) { Struct.new(:decision, :actions) }

  def run
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git,
                        handoff: handoff, prompt: prompt, start_ai_run: start_ai_run).call
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  def stub_decision(name, actions = [])
    allow(Stages::PrCheckDecision).to receive(:new).and_return(double(call: decision.new(name, actions)))
  end

  it "marks a merged PR merged without inspecting reviews" do
    allow(github).to receive(:merged?).and_return(true)
    allow(github).to receive(:review_decision)
    run

    expect(workflow.reload.status).to eq "merged"
    expect(actions).to eq %w[pr_merged_closed]
    expect(github).not_to have_received(:review_decision)
    expect(start_ai_run).not_to have_received(:call)
  end

  it "closes an approved PR as done, logging the decision actions first" do
    stub_decision(:approved, %w[check_passed])
    run

    expect(workflow.reload.status).to eq "done"
    expect(actions).to eq %w[check_passed approved_closed]
    expect(start_ai_run).not_to have_received(:call)
  end

  it "starts the review-fix run when changes are requested and main merges cleanly" do
    stub_decision(:changes_requested)
    run

    expect(git).to have_received(:update_with_main!).with(project, "pr-check-run")
    expect(start_ai_run).to have_received(:call).with("the prompt")
    expect(actions).to be_empty
  end

  it "starts conflict resolution when main conflicts" do
    stub_decision(:changes_requested)
    allow(git).to receive(:update_with_main!).and_return(:conflict)
    run

    expect(start_ai_run).to have_received(:call).with(Prompts::StagePrompt::CONFLICT, action: "conflict_resolution_started")
  end

  it "logs no_action_pending when nothing is decided" do
    stub_decision(:pending)
    run

    expect(actions).to eq %w[no_action_pending]
    expect(start_ai_run).not_to have_received(:call)
  end

  it "propagates a git error without starting the agent" do
    stub_decision(:changes_requested)
    allow(git).to receive(:update_with_main!).and_raise(Git::CommandError, "nope")

    expect { run }.to raise_error(Git::CommandError, "nope")
    expect(start_ai_run).not_to have_received(:call)
  end
end
