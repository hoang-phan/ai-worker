require "rails_helper"

RSpec.describe "check/verify loop prompts", type: :service do
  let(:project) { build_ci_project(ci_instructions: "RUN BIN CI FIRST", ci_verify_instructions: "yarn jest <file>", pr_instructions: "STATE ROLLBACK") }
  let(:workflow) { build_ci_workflow(project, ci_output_path: "/tmp/ci.log", ci_exit_status: 1) }

  def body(type) = Prompts::StagePrompt.new(workflow, workflow.stages.find_by!(stage_type: type)).body

  it "seeds the loop's stages for a new workflow, and none of the plain implementation" do
    expect(workflow.stages.pluck(:stage_type)).to eq %w[simple_implementation ci_check ci_verify pr_create pr_check]
  end

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

  it "does not touch a standard project's workflows" do
    standard = build_ci_project(flow: :standard, ci_command: nil)
    plain = build_ci_workflow(standard)
    expect(plain.stages.pluck(:stage_type)).to eq %w[implementation pr_check]
    expect(plain.current_stage.stage_type).to eq "implementation"
  end

  it "resolves implementing to the simple implementation stage on the loop flow" do
    expect(workflow.current_stage.stage_type).to eq "simple_implementation"
    workflow.update!(status: :reviewing)
    expect(workflow.current_stage.stage_type).to eq "pr_check"
  end
end

RSpec.describe "PR skills", type: :service do
  let(:project) { build_ci_project(default_skills: "impl-skill", default_pr_skills: "/github-pr-description") }

  it "renders {PR_SKILLS} in the PR prompt and keeps {SKILLS} for implementation" do
    workflow = build_ci_workflow(project, skills: project.default_skills, pr_skills: project.default_pr_skills)

    pr = Prompts::StagePrompt.new(workflow, workflow.stages.find_by!(stage_type: :pr_create)).body
    impl = Prompts::StagePrompt.new(workflow, workflow.stages.find_by!(stage_type: :simple_implementation)).body

    expect(pr).to include("/github-pr-description")
    expect(pr).not_to include("impl-skill")
    expect(impl).to include("impl-skill")
    expect(impl).not_to include("github-pr-description")
  end
end
