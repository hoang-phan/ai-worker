require "rails_helper"

RSpec.describe Workflows::CiLoopResume do
  let(:project) { build_ci_project }
  let(:workflow) { build_ci_workflow(project, status: :errored) }

  def status = described_class.new(workflow).status

  it "is nil when the project is on the standard flow" do
    project.update!(flow: :standard)
    workflow.stages.find_by!(stage_type: :implementation).log_run!("failed")
    expect(status).to be_nil
  end

  it "resumes the step whose newest run it was" do
    workflow.stages.find_by!(stage_type: :simple_implementation).log_run!("ran_implementation")
    expect(status).to eq :opening_pr

    workflow.stages.find_by!(stage_type: :pr_create).log_run!("pr_created")
    expect(status).to eq :ci_checking

    check = workflow.stages.find_by!(stage_type: :ci_check)
    check.log_run!("failed")
    expect(status).to eq :ci_checking

    check.log_run!("ci_check_completed")
    expect(status).to eq :ci_verifying

    verify = workflow.stages.find_by!(stage_type: :ci_verify)
    verify.log_run!("failed")
    expect(status).to eq :ci_verifying

    verify.log_run!("ci_rounds_exhausted")
    expect(status).to eq :ci_checking
  end

  it "retries the PR stage when it failed, and falls back once the checks passed" do
    workflow.stages.find_by!(stage_type: :pr_create).log_run!("failed")
    expect(status).to eq :opening_pr

    workflow.stages.find_by!(stage_type: :ci_verify).log_run!("ci_verify_passed")
    expect(status).to be_nil
  end

  it "feeds Workflow#resume_status" do
    workflow.stages.find_by!(stage_type: :ci_check).log_run!("ci_check_completed")
    expect(workflow.resume_status).to eq :ci_verifying
  end
end
