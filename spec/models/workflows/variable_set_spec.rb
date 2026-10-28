require "rails_helper"

RSpec.describe Workflows::VariableSet do
  let_jira_project("variable-set-spec", repo_full_name: "org/repo")
  let(:runbook) { build_runbook_workflow(project, variables: { "CHANNEL" => "#ops", "PR_URL" => "typed" }) }
  let!(:step) { build_runbook_stage(runbook, name: "Step") }
  let!(:other) { build_runbook_stage(runbook, name: "Other") }
  let(:variable_set) { described_class.new(runbook) }

  describe "stage output variables" do
    it "collects names from every completed run, across stages and runs" do
      step.log_run!("stage_completed", output: "VAR: PR_URL=http://x")
      step.log_run!("stage_completed", output: "VAR: EXTRA=1")
      other.log_run!("stage_completed", output: "VAR_BEGIN: NOTES\nl1\nVAR_END")

      expect(variable_set.output_variable_names).to match_array(%w[PR_URL EXTRA NOTES])
      expect(variable_set.input_variables).to eq("CHANNEL" => "#ops")
    end

    it "ignores failed and started rows" do
      step.log_run!("failed", output: "VAR: PR_URL=http://x", error: "boom")
      step.log_run!("started", output: "VAR: OTHER=1")

      expect(variable_set.output_variable_names).to eq([])
      expect(variable_set.input_variables).to eq("CHANNEL" => "#ops", "PR_URL" => "typed")
    end

    it "is empty with no runs" do
      expect(variable_set.output_variable_names).to eq([])
    end
  end

  it "reads and writes the UI text form" do
    expect(variable_set.variables_text).to eq("CHANNEL=#ops\nPR_URL=typed")

    variable_set.variables_text = "branch=main"

    expect(runbook.variables).to eq("BRANCH" => "main")
  end
end
