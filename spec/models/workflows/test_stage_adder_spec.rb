require "rails_helper"

RSpec.describe Workflows::TestStageAdder do
  let_jira_project("test-stage-adder-spec")
  let(:workflow) { build_jira_workflow(project, status: :pending) }

  def credentials(kind) = { "#{kind}_url": "http://x.example.com", "#{kind}_username": "u", "#{kind}_password": "p" }

  it "offers nothing while the project has no test credentials" do
    expect(workflow.addable_test_stages).to eq []
    expect(workflow.add_test_stage!("local_test")).to be false
  end

  it "offers each stage once its credentials are saved, and adds it" do
    project.update!(**credentials(:local), **credentials(:uat))

    expect(workflow.addable_test_stages).to eq %w[local_test uat_test]
    expect(workflow.add_test_stage!("local_test")).to be true
    expect(workflow.stages.pluck(:stage_type)).to include("local_test")
    expect(workflow).to be_local_test_stage
    expect(workflow.addable_test_stages).to eq %w[uat_test]
  end

  it "refuses an unknown stage type" do
    project.update!(**credentials(:local))

    expect(workflow.add_test_stage!("pr_check")).to be false
  end

  it "stops offering the local test once the PR has been handed off, but still offers UAT until the Jira update" do
    project.update!(**credentials(:local), **credentials(:uat))
    workflow.update!(status: :reviewing)

    expect(workflow.addable_test_stages).to eq %w[uat_test]

    workflow.update!(status: :jira_updated)
    expect(workflow.addable_test_stages).to eq []
  end

  it "does not apply to runbooks or PR reviews" do
    project.update!(**credentials(:local))
    runbook = build_runbook_workflow(project)

    expect(runbook.addable_test_stages).to eq []
  end
end
