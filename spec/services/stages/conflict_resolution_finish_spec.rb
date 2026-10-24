require "rails_helper"

RSpec.describe Stages::ConflictResolutionFinish, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "CRF-1", branch_name: "conflict-finish", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_check, name: "pr_check") }
  let(:git) { double("Git::BranchService", merge_in_progress?: false, abort_merge!: nil) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:launcher) { spy("launcher") }

  def finish(output = "merged")
    described_class.new(workflow: workflow, stage: stage, project: project, git: git,
                        prompt: prompt, launcher: launcher).call(output)
  end

  it "aborts the merge and raises when the merge is still in progress" do
    allow(git).to receive(:merge_in_progress?).and_return(true)

    expect { finish }.to raise_error(AiCli::CommandError, /did not finish resolving merge conflicts with main/)
    expect(git).to have_received(:abort_merge!).with(project)
    expect(stage_actions(stage)).to be_empty
    expect(launcher).not_to have_received(:call)
  end

  it "names the CLI the run used (the workflow's ai_provider) in the error" do
    workflow.update!(ai_provider: "codex")
    allow(git).to receive(:merge_in_progress?).and_return(true)

    expect { finish }.to raise_error(AiCli::CommandError, /\Acodex did not finish/)
  end

  it "resets the run, logs conflicts_resolved and starts the review-fix run once the merge is committed" do
    finish("all good")

    expect(workflow.reload).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil)
    expect(stage_actions(stage)).to eq %w[conflicts_resolved]
    expect(stage.stage_runs.last.output).to eq "all good"
    expect(git).not_to have_received(:abort_merge!)
    expect(launcher).to have_received(:call).with("the prompt")
  end
end
