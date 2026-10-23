require "rails_helper"

RSpec.describe Stages::ReviewHandoff, type: :service do
  let_tmpdir(:local_directory, "review-handoff-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "REV-1", branch_name: "review-handoff",
                                 github_reviewer: reviewers, github_pr_url: pr_url, status: :reviewing)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_check) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/12" }
  let(:reviewers) { "octocat, hubot" }
  let(:notifier) { instance_double(Slack::ReviewNotifier, enabled?: notifier_enabled, collect: nil) }
  let(:notifier_enabled) { true }
  let(:github) { instance_double(Github::Client) }

  subject(:handoff) { described_class.new(workflow, stage, notifier: notifier, github: github) }

  describe "#notify_reviewers!" do
    it "does nothing when Slack notifications are disabled" do
      allow(notifier).to receive(:enabled?).and_return(false)
      expect(notifier).not_to receive(:notify!)

      handoff.notify_reviewers!

      expect(stage.stage_runs).to be_empty
    end

    context "with no reviewers" do
      it "does not call Slack or create a StageRun" do
        workflow.update_column(:github_reviewer, nil)
        expect(notifier).not_to receive(:notify!)

        handoff.notify_reviewers!

        expect(stage.stage_runs).to be_empty
      end
    end

    it "notifies without a thread on the first notification and leaves the thread timestamp unset" do
      allow(github).to receive(:pr_title).with(pr_url).and_return("Fix handoff")
      expect(notifier).to receive(:notify!).with(hash_including(thread_ts: nil))

      handoff.notify_reviewers!

      expect(workflow.reload.slack_review_thread_ts).to be_nil
      expect(stage.stage_runs.last.action).to eq("slack_review_notified")
    end

    it "passes through an existing thread timestamp without overwriting it" do
      workflow.update!(slack_review_thread_ts: "existing-thread")
      allow(github).to receive(:pr_title).with(pr_url).and_return("Fix handoff")
      expect(notifier).to receive(:notify!).with(
        workflow: workflow, pr_url: pr_url, label: "REV-1 Fix handoff", reviewers: %w[octocat hubot],
        again: false, fixed: nil, thread_ts: "existing-thread"
      )

      handoff.notify_reviewers!

      expect(workflow.reload.slack_review_thread_ts).to eq("existing-thread")
    end

    it "uses the PR URL as the label when neither ticket nor title is available" do
      workflow.update_column(:jira_ticket, nil)
      allow(github).to receive(:pr_title).with(pr_url).and_return(nil)
      expect(notifier).to receive(:notify!).with(hash_including(label: pr_url))

      handoff.notify_reviewers!
    end

    it "falls back to the PR URL when there is no Jira ticket and the title is blank" do
      workflow.update_column(:jira_ticket, nil)
      allow(github).to receive(:pr_title).with(pr_url).and_return("")
      expect(notifier).to receive(:notify!).with(hash_including(label: pr_url))

      handoff.notify_reviewers!
    end

    it "labels with the title alone when there is no Jira ticket" do
      workflow.update_column(:jira_ticket, nil)
      allow(github).to receive(:pr_title).with(pr_url).and_return("Fix handoff")
      expect(notifier).to receive(:notify!).with(hash_including(label: "Fix handoff"))

      handoff.notify_reviewers!
    end

    it "posts into the thread_ts recorded by the ping collection" do
      allow(github).to receive(:pr_title).with(pr_url).and_return("Fix handoff")
      allow(notifier).to receive(:collect) { workflow.update_column(:slack_review_thread_ts, "collected-thread") }
      expect(notifier).to receive(:notify!).with(hash_including(thread_ts: "collected-thread"))

      handoff.notify_reviewers!

      expect(stage.stage_runs.last.action).to eq("slack_review_notified")
    end

    [ Slack::NotifyError, Github::CommandError ].each do |error_class|
      it "logs #{error_class} without raising" do
        if error_class == Slack::NotifyError
          allow(github).to receive(:pr_title).with(pr_url).and_return("Fix handoff")
          allow(notifier).to receive(:notify!).and_raise(error_class, "unavailable")
        else
          allow(github).to receive(:pr_title).with(pr_url).and_raise(error_class, "unavailable")
        end

        expect { handoff.notify_reviewers! }.not_to raise_error
        run = stage.stage_runs.last
        expect(run.action).to eq("slack_review_notify_failed")
        expect(run.error).to eq("unavailable")
      end
    end
  end

  describe "#enable_auto_merge!" do
    it "logs successful auto-merge activation" do
      allow(github).to receive(:enable_auto_merge!).with(pr_url)

      handoff.enable_auto_merge!(pr_url)

      expect(stage.stage_runs.last.action).to eq("auto_merge_enabled")
    end

    it "logs a GitHub failure without raising" do
      allow(github).to receive(:enable_auto_merge!).with(pr_url).and_raise(Github::CommandError, "not allowed")

      expect { handoff.enable_auto_merge!(pr_url) }.not_to raise_error
      run = stage.stage_runs.last
      expect(run.action).to eq("auto_merge_failed")
      expect(run.error).to eq("not allowed")
    end
  end
end
