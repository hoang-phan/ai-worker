require "rails_helper"

RSpec.describe Stages::CiCheckStart, type: :service do
  let_jira_project("ci-check-start-spec")
  let(:workflow) { build_ci_workflow(project) }
  let(:stage) { workflow.stages.create!(stage_type: :ci_check, name: "CI check") }
  let(:launcher) { spy("Stages::AiRunLauncher") }

  def start
    described_class.new(stage: stage, project: project, launcher: launcher).call
  end

  it "starts the stage command when one is present" do
    stage.update!(command: "bin/stage-ci")
    project.update!(ci_command: "bin/project-ci")

    start

    expect(launcher).to have_received(:call).with("bin/stage-ci")
  end

  it "starts the project CI command when the stage command is blank" do
    stage.update!(command: "")
    project.update!(ci_command: "bin/project-ci")

    start

    expect(launcher).to have_received(:call).with("bin/project-ci")
  end

  it "raises without launching when neither CI command is present" do
    stage.update!(command: "")
    project.update!(ci_command: "")

    expect { start }.to raise_error(ArgumentError, "project #{project.name} has no CI command for the check stage")
    expect(launcher).not_to have_received(:call)
  end
end
