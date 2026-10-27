require "rails_helper"

RSpec.describe Workflows::ProposalWorkflow do
  let_tmpdir(:local_directory, "proposal-workflow-spec")
  let(:project) { build_personal_project(local_directory: local_directory, default_skills: "ruby") }
  let(:proposal) { { "summary" => "Alpha", "task" => "Do it" } }
  let(:builder) { described_class.new(project) }

  def build(proposal, merge_skills: true)
    builder.build(proposal, merge_skills: merge_skills)
  end

  it "returns an unsaved development workflow with the proposal's summary and task" do
    workflow = build(proposal)

    expect(workflow).to be_new_record
    expect(workflow.project).to eq(project)
    expect(workflow).to be_development
    expect(workflow.summary).to eq("Alpha")
    expect(workflow.task_description).to eq("Do it")
  end

  it "sets pending status by default" do
    expect(build(proposal).status).to eq("pending")
  end

  it "sets implementing status when the project auto-starts brainstorm workflows" do
    project.update!(brainstorm_auto_start: true)

    expect(build(proposal).status).to eq("implementing")
  end

  it "takes the project's next workflow position" do
    expect(build(proposal).position).to eq(project.next_workflow_position)
    build(proposal).save!
    expect(build(proposal.merge("summary" => "Beta")).position).to eq(2)
  end

  describe "with merge_skills" do
    it "puts default skills first, then the proposal's, deduped" do
      workflow = build(proposal.merge("skills" => "ai-worker-testing, ruby"))

      expect(workflow.skills).to eq("ruby, ai-worker-testing")
    end

    it "strips and drops blank entries" do
      expect(build(proposal.merge("skills" => " a ,, b ")).skills).to eq("ruby, a, b")
    end

    it "falls back to default skills when the proposal has none" do
      expect(build(proposal.merge("skills" => nil)).skills).to eq("ruby")
      expect(build(proposal).skills).to eq("ruby")
    end
  end

  describe "without merge_skills" do
    it "uses the project's default skills only" do
      workflow = build(proposal.merge("skills" => "ai-worker-testing"), merge_skills: false)

      expect(workflow.skills).to eq("ruby")
    end
  end
end
