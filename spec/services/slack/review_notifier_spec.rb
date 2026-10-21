require "rails_helper"

RSpec.describe Slack::ReviewNotifier do
  let(:project) { instance_double(Project, slack_review_channel: "C123", slack_user_id_for: nil) }
  let(:notifier) { described_class.new(project) }
  let(:workflow) { instance_double(Workflow, id: 987_654_321, slack_review_thread_ts: nil) }
  let(:dir) { described_class::ROOT.join(workflow.id.to_s) }

  after { FileUtils.rm_rf(dir) }

  describe "#message" do
    it "delegates to Slack::ReviewMessage with the project's Slack id lookup" do
      allow(project).to receive(:slack_user_id_for).with("bob").and_return("U1")
      text = notifier.message(pr_url: "https://github.com/o/r/pull/1", label: "ENG-1 [x]", reviewers: %w[bob amy])
      expect(text).to eq(":eyes: <@U1> @amy please review [ENG-1 (x)](https://github.com/o/r/pull/1)")
    end
  end

  describe "#notify!" do
    it "starts a restricted detached run and records its pid" do
      expect(AiCli::Runner).to receive(:start).with(anything, a_string_including("thread_ts: 1.2"), hash_including(allowed_tools: described_class::ALLOWED_TOOLS)).and_return(42)
      notifier.notify!(workflow: workflow, pr_url: "u", label: "l", reviewers: [], thread_ts: "1.2")
      expect(Dir.glob(dir.join("*", "pid")).map { |f| File.read(f) }).to eq([ "42" ])
    end

    it "raises without a channel" do
      allow(project).to receive(:slack_review_channel).and_return(nil)
      expect { notifier.notify!(workflow: workflow, pr_url: "u", label: "l", reviewers: []) }.to raise_error(Slack::NotifyError)
    end
  end

  describe "#collect" do
    def ping(pid:, log:)
      path = dir.join(Time.current.to_i.to_s)
      FileUtils.mkdir_p(path)
      path.join("pid").write(pid)
      path.join("agent.log").write(log)
    end

    it "saves the permalink as the thread once the run finished" do
      ping(pid: 42, log: "Posted.\nhttps://ws.slack.com/archives/C123/p1760000000123456\n")
      allow(AiCli::Runner).to receive(:poll).with(42).and_return([ :completed, nil ])
      expect(workflow).to receive(:update!).with(slack_review_thread_ts: "https://ws.slack.com/archives/C123/p1760000000123456")
      expect(notifier.collect(workflow)).to be(false)
      expect(dir).not_to exist
    end

    it "waits while the run is alive" do
      ping(pid: 42, log: "")
      allow(AiCli::Runner).to receive(:poll).and_return(:running)
      expect(workflow).not_to receive(:update!)
      expect(notifier.collect(workflow)).to be(true)
    end
  end
end
