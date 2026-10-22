require "rails_helper"

RSpec.describe Workflows::CurrentStage do
  let(:local_directory) { Dir.mktmpdir("current-stage-spec") }
  let(:project_attrs) { { name: "Current stage spec", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory } }
  let(:project) { Project.create!(project_attrs) }
  let(:workflow) do
    project.workflows.create!(jira_ticket: "CS-1", branch_name: "cs-1", github_reviewer: "someone", status: :implementing)
  end

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  def call(wf = workflow) = described_class.new(wf).call

  describe "runbooks" do
    let(:runbook) { project.workflows.create!(kind: :runbook, status: :waiting) }
    let!(:first) { runbook.stages.create!(stage_type: :runbook_step, name: "One", position: 1) }
    let!(:second) { runbook.stages.create!(stage_type: :runbook_step, name: "Two", position: 2) }

    it "returns the stage at current_stage_id" do
      runbook.update!(current_stage_id: second.id)
      expect(call(runbook)).to eq(second)
    end

    it "returns nil when current_stage_id is unset" do
      expect(call(runbook)).to be_nil
    end
  end

  it "returns the seeded implementation stage of a jira development workflow" do
    expect(call).to eq(workflow.stages.find_by!(stage_type: :implementation))
  end

  it "maps implementing to a lazily created simple_implementation stage on a ci_loop project" do
    project.update!(flow: :ci_loop, ci_command: "bin/ci")
    workflow.stages.where(stage_type: :simple_implementation).destroy_all

    stage = nil
    expect { stage = call }.to change { workflow.stages.simple_implementation.count }.from(0).to(1)
    expect(stage).to be_simple_implementation
  end

  it "creates a lazy stage type once and reuses it" do
    workflow.update!(status: :merged)

    first = nil
    expect { first = call }.to change { workflow.stages.jira_update.count }.from(0).to(1)
    expect(first).to be_jira_update
    expect { expect(call).to eq(first) }.not_to change { Stage.count }
  end

  it "maps implementing to the task stage on a personal project" do
    personal = Project.create!(name: "Personal spec", kind: :personal, local_directory: local_directory)
    task = personal.workflows.create!(task_description: "Do it", status: :implementing)
    expect(call(task)).to eq(task.stages.find_by!(stage_type: :task))
  end

  it "maps a pr_review workflow to its pr_review stage" do
    review = project.workflows.create!(kind: :pr_review, github_pr_url: "https://github.com/org/repo/pull/7", status: :implementing)
    expect(call(review)).to eq(review.stages.find_by!(stage_type: :pr_review))
  end

  it "returns nil for a terminal status" do
    workflow.update!(status: :done)
    expect(call).to be_nil
  end
end
