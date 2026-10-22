require "rails_helper"

RSpec.describe Slack::ReviewNotifier do
  let(:project) { instance_double(Project, slack_review_channel: "C123", slack_user_id_for: nil) }
  let(:tmp_root) { Pathname(Dir.mktmpdir("slack_pings_spec")) }
  let(:runner) { double("runner", start: 42, poll: nil) }
  let(:notifier) { described_class.new(project, runner: runner, root: tmp_root) }
  let(:workflow) { instance_double(Workflow, id: 987_654_321, slack_review_thread_ts: nil) }
  let(:dir) { tmp_root.join(workflow.id.to_s) }

  after { FileUtils.remove_entry(tmp_root) if tmp_root.exist? }

  describe "#message" do
    it "delegates to Slack::ReviewMessage with the project's Slack id lookup" do
      allow(project).to receive(:slack_user_id_for).with("bob").and_return("U1")
      text = notifier.message(pr_url: "https://github.com/o/r/pull/1", label: "ENG-1 [x]", reviewers: %w[bob amy])
      expect(text).to eq(":eyes: <@U1> @amy please review [ENG-1 (x)](https://github.com/o/r/pull/1)")
    end
  end

  describe "#notify!" do
    let(:now) { Time.zone.at(1_760_000_000) }
    let(:notifier) { described_class.new(project, runner: runner, clock: -> { now }, root: tmp_root) }
    let(:run_dir) { tmp_root.join(workflow.id.to_s, "1760000000") }

    def notify(**opts)
      notifier.notify!(workflow: workflow, pr_url: "u", label: "l", reviewers: [], **opts)
    end

    it "starts a restricted detached run" do
      notify(thread_ts: "1.2")
      expect(runner).to have_received(:start).with(
        run_dir.to_s, a_string_including("thread_ts: 1.2"),
        hash_including(log_path: run_dir.join("agent.log").to_s, allowed_tools: described_class::ALLOWED_TOOLS)
      )
    end

    it "returns nil; the thread id is collected later by PingCollector" do
      expect(notify).to be_nil
    end

    it "names the run dir after the clock" do
      notify
      expect(Dir.children(tmp_root.join(workflow.id.to_s))).to eq([ "1760000000" ])
    end

    it "writes the pid to <dir>/pid" do
      notify
      expect(run_dir.join("pid").read).to eq("42")
    end

    it "wraps a CommandError from the runner in NotifyError" do
      allow(runner).to receive(:start).and_raise(AiCli::CommandError, "boom")
      expect { notify }.to raise_error(Slack::NotifyError, /failed to start: boom/)
    end

    it "wraps a SystemCallError from the runner in NotifyError" do
      allow(runner).to receive(:start).and_raise(Errno::ENOENT, "claude")
      expect { notify }.to raise_error(Slack::NotifyError, /failed to start/)
    end

    it "raises without a channel and spawns nothing" do
      allow(project).to receive(:slack_review_channel).and_return(nil)
      expect { notify }.to raise_error(Slack::NotifyError, "Slack channel is not set")
      expect(runner).not_to have_received(:start)
      expect(Dir.children(tmp_root)).to be_empty
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
      allow(runner).to receive(:poll).with(42).and_return([ :completed, nil ])
      expect(workflow).to receive(:update!).with(slack_review_thread_ts: "https://ws.slack.com/archives/C123/p1760000000123456")
      expect(notifier.collect(workflow)).to be(false)
      expect(dir).not_to exist
    end

    it "waits while the run is alive" do
      ping(pid: 42, log: "")
      allow(runner).to receive(:poll).and_return(:running)
      expect(workflow).not_to receive(:update!)
      expect(notifier.collect(workflow)).to be(true)
    end

    it "delegates to an injected collector" do
      collector = instance_double(Slack::PingCollector, collect: true)
      notifier = described_class.new(project, runner: runner, root: tmp_root, collector: collector)
      expect(notifier.collect(workflow)).to be(true)
      expect(collector).to have_received(:collect).with(workflow)
    end
  end
end
