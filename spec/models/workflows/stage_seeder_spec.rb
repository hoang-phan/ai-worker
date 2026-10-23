require "rails_helper"

RSpec.describe Workflows::StageSeeder do
  let(:local_directory) { Dir.mktmpdir("stage-seeder-spec") }
  let(:project) { Project.create!(name: "Seeder spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  # Workflow's after_create runs the seeder, so creating the workflow is what seeds it.
  def stage_types(workflow) = workflow.stages.map(&:stage_type)

  it "seeds implementation and pr_check for a Jira development workflow" do
    workflow = project.workflows.create!(jira_ticket: "ABC-1", branch_name: "abc-1", github_reviewer: "octocat")

    expect(stage_types(workflow)).to eq(%w[implementation pr_check])
  end

  it "seeds a task stage for a personal project" do
    personal = Project.create!(name: "Seeder personal project", kind: :personal, local_directory: local_directory)
    workflow = personal.workflows.create!(task_description: "Do the thing")

    expect(stage_types(workflow)).to eq(%w[task])
  end

  it "seeds a pr_review stage for a PR review" do
    workflow = project.workflows.create!(kind: :pr_review, github_pr_url: "https://github.com/org/repo/pull/7")

    expect(stage_types(workflow)).to eq(%w[pr_review])
  end

  it "seeds the ci_loop stages for a new workflow, and none of the plain implementation" do
    workflow = build_ci_workflow(build_ci_project)

    expect(stage_types(workflow)).to eq(%w[simple_implementation ci_check ci_verify pr_create pr_check])
  end

  it "does not touch a standard project's workflows" do
    workflow = build_ci_workflow(build_ci_project(flow: :standard, ci_command: nil))

    expect(stage_types(workflow)).to eq(%w[implementation pr_check])
  end

  describe "runbooks" do
    it "seeds nothing without a copy source" do
      expect(project.workflows.create!(kind: :runbook).stages).to be_empty
    end

    it "copies every runbook attribute of the source's stages in order" do
      source = project.workflows.create!(kind: :runbook)
      source.stages.create!(stage_type: :runbook_step, name: "Announce", position: 2, run_mode: :message, channel: "#deploys",
                            prompt: "Deploying {VERSION}", auto_advance: true, wait_for_workflow: "deploy.yml")
      source.stages.create!(stage_type: :runbook_step, name: "Build", position: 1, run_mode: :agent, channel: nil,
                            prompt: "Build it", auto_advance: false, wait_for_workflow: nil)

      copy = project.workflows.create!(kind: :runbook, copy_stages_from_id: source.id)

      expect(copy.stages.map(&:stage_type).uniq).to eq(%w[runbook_step])
      expect(copy.stages.map { |s| s.slice(*described_class::COPIED_RUNBOOK_ATTRIBUTES) })
        .to eq(source.stages.map { |s| s.slice(*described_class::COPIED_RUNBOOK_ATTRIBUTES) })
      expect(copy.stages.map(&:name)).to eq(%w[Build Announce])
      announce = copy.stages.last
      expect(announce).to have_attributes(position: 2, run_mode: "message", channel: "#deploys", prompt: "Deploying {VERSION}",
                                          auto_advance: true, wait_for_workflow: "deploy.yml")
      expect(copy.stages.map(&:id) & source.stages.map(&:id)).to be_empty
    end
  end
end
