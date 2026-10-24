require "rails_helper"

RSpec.describe Stages::PrCreateFinish, type: :service do
  let(:project) { build_ci_project }
  let(:workflow) { build_ci_workflow(project, **running_ai_run) }
  let(:stage) { workflow.stages.create!(stage_type: :pr_create, name: "Create PR") }
  let(:github) { double("Github::Client") }
  let(:handoff) { double("Stages::ReviewHandoff") }
  let(:opened_finish) { instance_double(Stages::PrOpenedFinish, call: nil) }

  before { allow(Stages::PrOpenedFinish).to receive(:new).and_return(opened_finish) }

  it "delegates with the PR-created action and ci-loop check follow-up" do
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call("output")

    expect(Stages::PrOpenedFinish).to have_received(:new)
      .with(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
    expect(opened_finish).to have_received(:call).with("output", action: "pr_created", checks_follow: true)
  end

  it "does not schedule a check follow-up outside ci_loop" do
    allow(project).to receive(:ci_loop_ready?).and_return(false)

    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call("output")

    expect(opened_finish).to have_received(:call).with("output", action: "pr_created", checks_follow: false)
  end
end
