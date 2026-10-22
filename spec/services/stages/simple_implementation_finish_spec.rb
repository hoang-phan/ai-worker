require "rails_helper"

RSpec.describe Stages::SimpleImplementationFinish, type: :service do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) do
    build_ci_workflow(project, status: :ci_verifying, processing: true, ai_pid: 1, ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 7)
  end
  let(:stage) { workflow.stages.find_by!(stage_type: :simple_implementation) }

  def actions(stage) = stage.stage_runs.reorder(:id).pluck(:action)

  it "moves on to the PR stage without looking for a PR" do
    described_class.new(workflow: workflow, stage: stage).call("out")

    expect(workflow.reload).to have_attributes(status: "opening_pr", github_pr_url: nil)
    expect(actions(stage)).to eq %w[ran_implementation]
  end

  it "clears the AI run fields" do
    described_class.new(workflow: workflow, stage: stage).call("out")

    expect(workflow.reload).to have_attributes(Workflow::AI_RUN_RESET)
  end
end
