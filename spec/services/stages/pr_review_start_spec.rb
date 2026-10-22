require "rails_helper"

RSpec.describe Stages::PrReviewStart, type: :service do
  let(:project) { instance_double(Project) }
  let(:workflow) { instance_double(Workflow, github_pr_url: "https://github.com/acme/widgets/pull/1", update!: true) }
  let(:stage) { instance_double(Stage, log_run!: nil) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:github) { double("Github::Client", checkout_pr!: nil) }
  let(:git) { double("Git::BranchService", checkout_remote_branch!: nil) }
  let(:launcher) { spy("Stages::AiRunLauncher") }

  def start
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git,
                        prompt: prompt, launcher: launcher).call
  end

  %w[CLOSED MERGED].each do |state|
    it "marks the workflow done, logs the skip and never launches for a #{state} PR" do
      allow(github).to receive(:pr_info).and_return("state" => state)

      start

      expect(workflow).to have_received(:update!).with(status: :done)
      expect(stage).to have_received(:log_run!).with("pr_not_open_skipped")
      expect(launcher).not_to have_received(:call)
      expect(git).not_to have_received(:checkout_remote_branch!)
    end
  end

  it "uses gh to check out a cross-repository PR" do
    allow(github).to receive(:pr_info).with(workflow.github_pr_url).and_return("state" => "OPEN", "cross_repository" => true)

    start

    expect(github).to have_received(:checkout_pr!).with(workflow.github_pr_url)
    expect(git).not_to have_received(:checkout_remote_branch!)
    expect(launcher).to have_received(:call).with("the prompt")
  end

  it "checks out the head ref of a same-repo PR and launches with the prompt body" do
    allow(github).to receive(:pr_info).and_return("state" => "OPEN", "head_ref" => "feature")

    start

    expect(git).to have_received(:checkout_remote_branch!).with(project, "feature")
    expect(github).not_to have_received(:checkout_pr!)
    expect(launcher).to have_received(:call).with("the prompt")
  end

  it "propagates a checkout error without launching" do
    allow(github).to receive(:pr_info).and_return("state" => "OPEN", "head_ref" => "feature")
    allow(git).to receive(:checkout_remote_branch!).and_raise(Git::CommandError, "nope")

    expect { start }.to raise_error(Git::CommandError, "nope")
    expect(launcher).not_to have_received(:call)
  end
end
