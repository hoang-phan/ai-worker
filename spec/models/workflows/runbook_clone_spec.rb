require "rails_helper"

RSpec.describe Workflows::RunbookClone do
  let_tmpdir(:local_directory, "runbook-clone-spec")
  let(:project) { build_jira_project(repo_full_name: "org/repo", local_directory: local_directory) }
  let!(:source) do
    project.workflows.create!(kind: :runbook, position: 4, variables: { "CHANNEL" => "#ops", "VERSION" => "1.0" }).tap do |runbook|
      runbook.stages.create!(stage_type: :runbook_step, name: "Build", position: 1, prompt: "Build it")
      runbook.stages.create!(stage_type: :runbook_step, name: "Ship", position: 2, prompt: "Ship it")
    end
  end

  def clone_result = described_class.new(source).call

  it "refuses a workflow that is not a runbook" do
    development = build_jira_workflow(project, jira_ticket: "C-1", branch_name: "c-1")

    result = described_class.new(development).call

    expect(result.status).to eq(:not_runbook)
    expect(result.copy).to be_nil
  end

  it "creates a runbook copy at the next position with the same stages" do
    expected_position = project.next_workflow_position

    result = clone_result

    expect(result.status).to eq(:created)
    expect(result.copy).to be_persisted.and have_attributes(kind: "runbook", position: expected_position)
    expect(result.copy.stages.order(:position).pluck(:name, :prompt)).to eq([ [ "Build", "Build it" ], [ "Ship", "Ship it" ] ])
  end

  it "copies only input variables, dropping ones a stage emitted" do
    stage = source.stages.first
    StageRun.create!(stage: stage, action: "stage_completed", output: "done\nVAR: VERSION=1.0")

    expect(clone_result.copy.variables).to eq("CHANNEL" => "#ops")
  end

  it "returns the errors of an invalid copy" do
    allow_any_instance_of(Workflow).to receive(:input_variables).and_return({ "bad name" => "x" })

    result = clone_result

    expect(result.status).to eq(:invalid)
    expect(result.error).to include("Variables names must be letters")
    expect(result.copy).not_to be_persisted
  end
end
