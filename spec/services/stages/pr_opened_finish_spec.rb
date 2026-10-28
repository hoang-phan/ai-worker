require "rails_helper"

RSpec.describe Stages::PrOpenedFinish, type: :service do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) do
    build_ci_workflow(project, status: :ci_verifying, **running_ai_run)
  end
  let(:pr_url) { "https://github.com/acme/widgets/pull/9" }
  let(:github) { instance_double(Github::Client, find_pr_url: pr_url) }
  let(:handoff) { instance_double(Stages::ReviewHandoff, enable_auto_merge!: nil, notify_reviewers!: nil) }
  let(:stage) { workflow.stages.find_by!(stage_type: :pr_create) }

  def finish = described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call("out", action: "pr_created")

  it "records the PR, starts review, logs pr_created and hands the PR over" do
    finish

    expect(workflow.reload).to have_attributes(status: "reviewing", github_pr_url: pr_url).and have_finished_ai_run
    expect(stage_actions(stage)).to eq %w[pr_created]
    expect(handoff).to have_received(:enable_auto_merge!).with(pr_url)
    expect(handoff).to have_received(:notify_reviewers!)
  end

  it "goes to the CI check when checks follow, leaving the reviewer ping for after they pass" do
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff)
                   .call("out", action: "pr_created", checks_follow: true)

    expect(workflow.reload).to have_attributes(status: "ci_checking", github_pr_url: pr_url).and have_finished_ai_run
    expect(stage_actions(stage)).to eq %w[pr_created]
    expect(handoff).to have_received(:enable_auto_merge!).with(pr_url)
    expect(handoff).not_to have_received(:notify_reviewers!)
  end

  it "queues local testing instead of handing over when the project is local-test ready" do
    project.update!(local_test_enabled: true, local_url: "http://localhost:3000")
    expect(project).to be_local_test_ready

    finish

    expect(workflow.reload).to have_attributes(status: "local_testing", github_pr_url: pr_url).and have_finished_ai_run
    expect(stage_actions(stage)).to eq %w[pr_created]
    expect(handoff).not_to have_received(:enable_auto_merge!)
    expect(handoff).not_to have_received(:notify_reviewers!)
  end
end
