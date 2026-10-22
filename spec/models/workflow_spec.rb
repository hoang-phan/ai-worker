require "rails_helper"

RSpec.describe Workflow, type: :model do
  let(:local_directory) { Dir.mktmpdir("workflow-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:pr_url) { "https://github.com/org/repo/pull/7" }
  let(:workflow) do
    project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone", status: :pending)
  end

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "transition delegators" do
    it "delegates to Workflows::Transitions" do
      expect(workflow.start!).to be true
      expect(workflow.reload).to be_implementing
      workflow.update!(status: :errored)
      expect(workflow.resume_status).to eq(:implementing)
      expect(workflow.resume!).to be true
      expect(workflow).not_to be_can_rollback_to_review
      expect(workflow.rollback_to_review!).to be false
      expect(workflow).not_to be_can_run_stage
      expect(workflow.request_stage_run!).to be false
      expect(workflow).not_to be_can_advance
    end
  end

  describe "AI_RUN_RESET" do
    it "covers processing and every ai_* column" do
      expected = Workflow.column_names.grep(/\Aai_/) + %w[processing]
      expect(Workflow::AI_RUN_RESET.keys.map(&:to_s)).to match_array(expected)
    end
  end

  describe "#finish_ai_run!" do
    it "clears the ai run columns and applies the extra attributes in one update" do
      workflow.update!(processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 42)

      workflow.finish_ai_run!(auto_run: false)

      expect(workflow.reload).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil, ai_started_at: nil, ai_log_offset: 0, auto_run: false)
    end
  end

  describe "stage output variables" do
    let(:runbook) { project.workflows.create!(kind: :runbook, task_description: "rb", variables: { "CHANNEL" => "#ops", "PR_URL" => "typed" }) }
    let!(:step) { runbook.stages.create!(stage_type: :runbook_step, name: "Step") }
    let!(:other) { runbook.stages.create!(stage_type: :runbook_step, name: "Other") }

    after { runbook.destroy }

    it "collects names from every completed run, across stages and runs" do
      step.log_run!("stage_completed", output: "VAR: PR_URL=http://x")
      step.log_run!("stage_completed", output: "VAR: EXTRA=1")
      other.log_run!("stage_completed", output: "VAR_BEGIN: NOTES\nl1\nVAR_END")

      expect(runbook.output_variable_names).to match_array(%w[PR_URL EXTRA NOTES])
      expect(runbook.input_variables).to eq("CHANNEL" => "#ops")
    end

    it "ignores failed and started rows" do
      step.log_run!("failed", output: "VAR: PR_URL=http://x", error: "boom")
      step.log_run!("started", output: "VAR: OTHER=1")

      expect(runbook.output_variable_names).to eq([])
      expect(runbook.input_variables).to eq("CHANNEL" => "#ops", "PR_URL" => "typed")
    end

    it "is empty with no runs" do
      expect(runbook.output_variable_names).to eq([])
    end
  end
end
