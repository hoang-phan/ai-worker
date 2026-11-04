require "rails_helper"

RSpec.describe Workflows::ResumeStatus do
  let_jira_project("resume-status-spec")
  let(:workflow) { build_jira_workflow(project) }
  let(:pr_url) { "https://github.com/org/repo/pull/7" }

  def target(wf = workflow) = described_class.new(wf).call

  def stage_of(type, wf = workflow) = wf.stages.find_by!(stage_type: type)

  it "is the first stage without a PR or any run" do
    expect(target).to have_attributes(status: :implementing, stage: stage_of(:implementation))
  end

  it "is the review stage once a PR exists" do
    workflow.update!(github_pr_url: pr_url)

    expect(target).to have_attributes(status: :reviewing, stage: stage_of(:pr_check))
  end

  it "is the stored current stage ahead of any other rule" do
    workflow.update!(github_pr_url: pr_url, current_stage_id: stage_of(:implementation).id)

    expect(target).to have_attributes(status: :implementing, stage: stage_of(:implementation), origin: stage_of(:implementation))
  end

  it "is the stage of the newest run when no stage is stored" do
    enable_local_testing(workflow)
    workflow.update!(github_pr_url: pr_url)
    stage_of(:local_test).log_run!("started")

    expect(target).to have_attributes(status: :local_testing, stage: stage_of(:local_test))
  end

  it "ignores 'resumed' runs when finding the newest run" do
    workflow.update!(github_pr_url: pr_url)
    stage_of(:implementation).log_run!("ran_implementation")
    stage_of(:pr_check).log_run!("resumed")

    expect(target.stage).to eq stage_of(:implementation)
  end

  it "is implementing for a PR-review workflow with a PR" do
    review = build_pr_review_workflow(project, github_pr_url: pr_url)

    expect(target(review)).to have_attributes(status: :implementing, stage: stage_of(:pr_review, review))
  end

  it "is uat_testing when a UAT test was scheduled, ahead of everything else" do
    workflow.update!(uat_test_at: 1.hour.ago, current_stage_id: stage_of(:pr_check).id)

    expect(target).to have_attributes(status: :uat_testing, stage: nil)
  end

  it "leaves a runbook's stored stage alone" do
    runbook = build_runbook_workflow(project)

    expect(target(runbook)).to have_attributes(status: :implementing, stage: nil)
  end

  describe "an exhausted CI loop" do
    let(:project) { build_ci_project(ci_max_rounds: 2) }
    let(:workflow) { build_ci_workflow(project, github_pr_url: pr_url) }

    it "restarts at the verify stage's failure target, the check" do
      verify = stage_of(:ci_verify)
      workflow.update!(current_stage_id: verify.id)
      verify.log_run!("ci_verify_failed")
      verify.log_run!("ci_rounds_exhausted")

      expect(target).to have_attributes(status: :ci_checking, stage: stage_of(:ci_check), origin: verify)
    end

    it "resumes a verify error at the verify stage" do
      workflow.update!(current_stage_id: stage_of(:ci_verify).id)
      stage_of(:ci_verify).log_run!("failed")

      expect(target).to have_attributes(status: :ci_verifying, stage: stage_of(:ci_verify))
    end

    it "resumes opening the PR" do
      workflow.update!(current_stage_id: stage_of(:pr_create).id)

      expect(target).to have_attributes(status: :opening_pr, stage: stage_of(:pr_create))
    end
  end
end
