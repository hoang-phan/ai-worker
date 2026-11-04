require "rails_helper"

RSpec.describe Workflows::StageFlow do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) { build_ci_workflow(project, status: :implementing) }
  let(:flow) { described_class.new(workflow) }

  def stage(type) = workflow.stages.find_by!(stage_type: type)

  describe "#pipeline" do
    it "orders the stages by the pipeline order, not by creation" do
      expect(flow.pipeline.map(&:stage_type)).to eq %w[simple_implementation pr_create ci_check ci_verify pr_check]
    end

    it "puts a local_test stage added later before the review, only while the project can run it" do
      workflow.stages.create!(stage_type: :local_test)
      expect(flow.pipeline.map(&:stage_type)).not_to include("local_test")

      enable_local_testing(workflow)
      expect(flow.pipeline.map(&:stage_type)).to eq %w[simple_implementation pr_create ci_check ci_verify local_test pr_check]
    end

    it "leaves out post-merge stages" do
      workflow.stages.create!(stage_type: :jira_update)
      enable_uat_testing(workflow)

      expect(flow.pipeline.map(&:stage_type)).not_to include("jira_update", "uat_test")
    end
  end

  describe "#complete!" do
    it "enters the next stage with its status and the given attributes" do
      expect(flow.complete!(stage(:ci_check), ci_exit_status: 1)).to eq stage(:ci_verify)

      expect(workflow.reload).to have_attributes(status: "ci_verifying", current_stage_id: stage(:ci_verify).id, ci_exit_status: 1)
    end

    it "marks the workflow done after the last stage" do
      expect(flow.complete!(stage(:pr_check))).to be_nil

      expect(workflow.reload.status).to eq "done"
    end
  end

  describe "#failure_target" do
    it "defaults per stage type: verify -> check, review -> itself, local test -> review" do
      enable_local_testing(workflow)

      expect(flow.failure_target(stage(:ci_verify))).to eq stage(:ci_check)
      expect(flow.failure_target(stage(:pr_check))).to eq stage(:pr_check)
      expect(flow.failure_target(stage(:local_test))).to eq stage(:pr_check)
    end

    it "uses the stage selected on the stage" do
      stage(:pr_check).update!(failure_stage_id: stage(:ci_verify).id)

      expect(flow.failure_target(stage(:pr_check))).to eq stage(:ci_verify)
    end

    it "falls back to the default when the selected stage left the pipeline, and to the stage itself without a default" do
      local_test = workflow.stages.create!(stage_type: :local_test)
      stage(:pr_check).update!(failure_stage_id: local_test.id) # not runnable: no local credentials

      expect(flow.failure_target(stage(:pr_check))).to eq stage(:pr_check)
      expect(flow.failure_target(stage(:ci_check))).to eq stage(:ci_check)
    end
  end

  describe "#route_failed!" do
    it "enters the failure target, logs the route and applies the attributes" do
      expect(flow.route_failed!(stage(:ci_verify), local_test_feedback: "x")).to eq stage(:ci_check)

      expect(workflow.reload).to have_attributes(status: "ci_checking", current_stage_id: stage(:ci_check).id, local_test_feedback: "x")
      expect(stage(:ci_verify).stage_runs.pluck(:action, :output)).to eq [ [ "failure_routed", "back to Ci check" ] ]
    end

    it "parks the workflow errored instead of looping once the stage was routed back too many times" do
      review = stage(:pr_check)
      described_class::MAX_FAILURE_ROUNDS.times { review.log_run!("failure_routed") }

      expect(flow.route_failed!(review)).to be_nil

      expect(workflow.reload.status).to eq "errored"
      expect(review.last_action).to eq "failure_rounds_exhausted"
    end

    it "gives a resumed stage a fresh budget" do
      review = stage(:pr_check)
      described_class::MAX_FAILURE_ROUNDS.times { review.log_run!("failure_routed") }
      review.log_run!("resumed")

      expect(flow.route_failed!(review)).to eq review
    end
  end
end
