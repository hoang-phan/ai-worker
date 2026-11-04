require "rails_helper"

# The resume half of Workflows::Transitions: where an errored workflow goes back to (see Workflows::ResumeStatus).
RSpec.describe Workflows::Transitions, "resuming" do
  let_jira_project("transitions-resume-spec", repo_full_name: "org/repo")
  let(:pr_url) { "https://github.com/org/repo/pull/7" }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-2", branch_name: "spec-2", status: :pending)
  end
  let(:transitions) { described_class.new(workflow) }

  describe "#resume!" do
    before { workflow.update!(status: :errored) }

    it "refuses a workflow that is not errored" do
      workflow.update!(status: :reviewing)
      expect { expect(transitions.resume!).to be false }.not_to change(StageRun, :count)
      expect(workflow.reload).to be_reviewing
    end

    it "uses ResumeStatus and logs one 'resumed' StageRun on the resulting current stage" do
      workflow.update!(github_pr_url: pr_url)
      review = workflow.stages.find_by!(stage_type: :pr_check)
      target = Workflows::ResumeStatus::Target.new(status: :reviewing, stage: review, origin: review)
      resume_status = instance_double(Workflows::ResumeStatus, call: target)
      transitions = described_class.new(workflow, resume_status: resume_status)

      expect { expect(transitions.resume!).to be true }.to change(StageRun, :count).by(1)
      expect(workflow.reload).to be_reviewing
      expect(workflow.current_stage_id).to eq review.id
      expect(stage_actions(review)).to eq(%w[resumed])
    end

    it "logs 'resumed' on the errored stage too when it resumes at another one" do
      verify = build_stage(workflow, :ci_verify)
      check = build_stage(workflow, :ci_check)
      target = Workflows::ResumeStatus::Target.new(status: :ci_checking, stage: check, origin: verify)
      transitions = described_class.new(workflow, resume_status: instance_double(Workflows::ResumeStatus, call: target))

      expect(transitions.resume!).to be true
      expect(workflow.reload).to have_attributes(status: "ci_checking", current_stage_id: check.id)
      expect(stage_actions(check)).to eq(%w[resumed])
      expect(stage_actions(verify)).to eq(%w[resumed])
    end

    it "updates a runbook and logs one 'resumed' StageRun on its current stage" do
      runbook = build_runbook_workflow(project)
      step = build_runbook_stage(runbook, name: "One", position: 1)
      runbook.update!(status: :errored, current_stage_id: step.id)
      expect { expect(Workflows::Transitions.new(runbook).resume!).to be true }.to change(StageRun, :count).by(1)
      expect(runbook.reload).to be_implementing
      expect(stage_actions(step)).to eq(%w[resumed])
    end
  end

  describe "#resume_status" do
    it "forwards to ResumeStatus" do
      target = Workflows::ResumeStatus::Target.new(status: :reviewing)
      transitions = described_class.new(workflow, resume_status: instance_double(Workflows::ResumeStatus, call: target))

      expect(transitions.resume_status).to eq(:reviewing)
    end
  end
end
