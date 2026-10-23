require "rails_helper"

RSpec.describe Prompts::StagePrompt do
  context "on the ci_loop flow" do
    let(:project) { build_ci_project(ci_instructions: "RUN BIN CI FIRST", ci_verify_instructions: "yarn jest <file>", pr_instructions: "STATE ROLLBACK") }
    let(:workflow) { build_ci_workflow(project, ci_output_path: "/tmp/ci.log", ci_exit_status: 1) }

    def body(type) = described_class.new(workflow, workflow.stages.find_by!(stage_type: type)).body

    it "gives the simple implementation its own default prompt: no checks, no PR, no project CI text" do
      text = body(:simple_implementation)
      expect(text).to include("Do NOT run the project's full CI gate", "Do NOT push the branch")
      expect(text).not_to include("RUN BIN CI FIRST")
    end

    it "renders the verify prompt with the log, exit status and project hints" do
      text = body(:ci_verify)
      expect(text).to include("/tmp/ci.log", "exit status was 1", "yarn jest <file>", "CI_VERDICT: PASSED")
      expect(text).not_to include("RUN BIN CI FIRST")
    end

    it "renders the PR prompt with the project's PR instructions" do
      expect(body(:pr_create)).to include("STATE ROLLBACK")
    end

    context "with PR skills" do
      let(:project) { build_ci_project(default_skills: "impl-skill", default_pr_skills: "/github-pr-description") }
      let(:workflow) { build_ci_workflow(project, skills: project.default_skills, pr_skills: project.default_pr_skills) }

      it "renders {PR_SKILLS} in the PR prompt and keeps {SKILLS} for implementation" do
        pr = body(:pr_create)
        impl = body(:simple_implementation)

        expect(pr).to include("/github-pr-description")
        expect(pr).not_to include("impl-skill")
        expect(impl).to include("impl-skill")
        expect(impl).not_to include("github-pr-description")
      end
    end
  end
end
