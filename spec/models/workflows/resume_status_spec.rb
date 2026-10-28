require "rails_helper"

RSpec.describe Workflows::ResumeStatus do
  let_jira_project("resume-status-spec")
  let(:workflow) { build_jira_workflow(project) }
  let(:ci_status) { nil }
  let(:ci_loop_resume) { instance_double(Workflows::CiLoopResume, status: ci_status) }

  def status = described_class.new(workflow, ci_loop_resume: ci_loop_resume).call

  it "is implementing without a PR" do
    expect(status).to eq(:implementing)
  end

  it "is reviewing for a development workflow with a PR" do
    workflow.update!(github_pr_url: "https://github.com/org/repo/pull/7")

    expect(status).to eq(:reviewing)
  end

  it "is implementing for a PR-review workflow with a PR" do
    review = build_pr_review_workflow(project, github_pr_url: "https://github.com/org/repo/pull/7")

    expect(described_class.new(review, ci_loop_resume: ci_loop_resume).call).to eq(:implementing)
  end

  it "is local_testing when the newest local test run never finished" do
    local_test = build_stage(workflow, :local_test)
    local_test.log_run!("started")

    expect(status).to eq(:local_testing)
  end

  it "is reviewing when the newest local test run completed" do
    local_test = build_stage(workflow, :local_test)
    local_test.log_run!("local_test_completed")
    workflow.update!(github_pr_url: "https://github.com/org/repo/pull/7")

    expect(status).to eq(:reviewing)
  end

  it "is uat_testing when a UAT test was scheduled, ahead of local_testing" do
    local_test = build_stage(workflow, :local_test)
    local_test.log_run!("started")
    workflow.update!(uat_test_at: 1.hour.ago)

    expect(status).to eq(:uat_testing)
  end

  it "uses the CI loop resume status ahead of local testing" do
    local_test = build_stage(workflow, :local_test)
    local_test.log_run!("started")
    allow(ci_loop_resume).to receive(:status).and_return(:ci_verifying)

    expect(status).to eq(:ci_verifying)
  end

  it "uses UAT testing ahead of the CI loop resume status" do
    workflow.update!(uat_test_at: 1.hour.ago)
    allow(ci_loop_resume).to receive(:status).and_return(:ci_verifying)

    expect(status).to eq(:uat_testing)
  end
end
