require "rails_helper"

RSpec.describe Workflows::ResumeStatus do
  let(:workflow) do
    instance_double(
      Workflow,
      uat_test_at: nil,
      stages: stages,
      development?: development,
      github_pr_url: github_pr_url
    )
  end
  let(:stages) { instance_double(ActiveRecord::Associations::CollectionProxy, find_by: local_test_stage) }
  let(:local_test_stage) { nil }
  let(:development) { true }
  let(:github_pr_url) { nil }

  def status = described_class.new(workflow).call

  before do
    allow(Workflows::CiLoopResume).to receive(:new).with(workflow).and_return(instance_double(Workflows::CiLoopResume, status: ci_status))
  end

  let(:ci_status) { nil }

  it "is implementing without a PR" do
    expect(status).to eq(:implementing)
  end

  it "is reviewing for a development workflow with a PR" do
    allow(workflow).to receive(:github_pr_url).and_return("https://github.com/org/repo/pull/7")

    expect(status).to eq(:reviewing)
  end

  it "is implementing for a PR-review workflow with a PR" do
    allow(workflow).to receive(:development?).and_return(false)
    allow(workflow).to receive(:github_pr_url).and_return("https://github.com/org/repo/pull/7")

    expect(status).to eq(:implementing)
  end

  it "is local_testing when the newest local test run never finished" do
    local_test = instance_double(Stage, local_test_unfinished?: true)
    allow(stages).to receive(:find_by).with(stage_type: :local_test).and_return(local_test)

    expect(status).to eq(:local_testing)
  end

  it "is reviewing when the newest local test run completed" do
    local_test = instance_double(Stage, local_test_unfinished?: false)
    allow(stages).to receive(:find_by).with(stage_type: :local_test).and_return(local_test)
    allow(workflow).to receive(:github_pr_url).and_return("https://github.com/org/repo/pull/7")

    expect(status).to eq(:reviewing)
  end

  it "is uat_testing when a UAT test was scheduled, ahead of local_testing" do
    local_test = instance_double(Stage, local_test_unfinished?: true)
    allow(workflow).to receive(:uat_test_at).and_return(1.hour.ago)
    allow(stages).to receive(:find_by).with(stage_type: :local_test).and_return(local_test)

    expect(status).to eq(:uat_testing)
  end

  it "uses the CI loop resume status ahead of local testing" do
    local_test = instance_double(Stage, local_test_unfinished?: true)
    allow(stages).to receive(:find_by).with(stage_type: :local_test).and_return(local_test)
    allow(Workflows::CiLoopResume).to receive(:new).with(workflow).and_return(instance_double(Workflows::CiLoopResume, status: :ci_verifying))

    expect(status).to eq(:ci_verifying)
  end

  it "uses UAT testing ahead of the CI loop resume status" do
    allow(workflow).to receive(:uat_test_at).and_return(1.hour.ago)
    allow(Workflows::CiLoopResume).to receive(:new).with(workflow).and_return(instance_double(Workflows::CiLoopResume, status: :ci_verifying))

    expect(status).to eq(:uat_testing)
  end
end
