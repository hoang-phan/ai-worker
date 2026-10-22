require "rails_helper"

RSpec.describe Stages::ConflictResolutionFinish, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "CRF-1", branch_name: "conflict-finish", status: :implementing,
                                 processing: true, ai_pid: 1, ai_log_path: "/tmp/x.log", ai_log_offset: 5)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_check, name: "pr_check") }
  let(:git) { double("Git::BranchService", merge_in_progress?: false, abort_merge!: nil) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:start_ai_run) { spy("start_ai_run") }

  def finish(output = "merged")
    described_class.new(workflow: workflow, stage: stage, project: project, git: git,
                        prompt: prompt, start_ai_run: start_ai_run).call(output)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  it "aborts the merge and raises when the merge is still in progress" do
    allow(git).to receive(:merge_in_progress?).and_return(true)

    expect { finish }.to raise_error(AiCli::CommandError, /did not finish resolving merge conflicts with main/)
    expect(git).to have_received(:abort_merge!).with(project)
    expect(actions).to be_empty
    expect(start_ai_run).not_to have_received(:call)
  end

  it "resets the run, logs conflicts_resolved and starts the review-fix run once the merge is committed" do
    finish("all good")

    expect(workflow.reload).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil)
    expect(actions).to eq %w[conflicts_resolved]
    expect(stage.stage_runs.last.output).to eq "all good"
    expect(git).not_to have_received(:abort_merge!)
    expect(start_ai_run).to have_received(:call).with("the prompt")
  end
end
