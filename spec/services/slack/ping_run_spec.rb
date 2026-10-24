require "rails_helper"
require "tmpdir"

RSpec.describe Slack::PingRun do
  let(:tmp_root) { Pathname(make_tmpdir("ping_run_spec")) }
  let(:dir) { tmp_root.join("7", "1700000000").tap { |d| FileUtils.mkdir_p(d) } }
  let(:run) { described_class.new(dir) }

  it "builds the dir for a workflow and start time" do
    built = described_class.for(tmp_root, 7, Time.zone.at(1_700_000_000))
    expect(built.dir).to eq(dir)
  end

  it "names the pid and log files" do
    expect(run.pid_file).to eq(dir.join("pid"))
    expect(run.log_file).to eq(dir.join("agent.log"))
  end

  it "reads started_at from the dir basename" do
    expect(run.started_at).to eq(Time.zone.at(1_700_000_000))
  end

  describe "#stale?" do
    it "is fresh within STALE_AFTER" do
      expect(run.stale?(run.started_at + 4.minutes)).to be(false)
    end

    it "is stale after STALE_AFTER" do
      expect(run.stale?(run.started_at + 6.minutes)).to be(true)
    end
  end

  describe "#permalink" do
    it "is nil without a log" do
      expect(run.permalink).to be_nil
    end

    it "is nil when the log has no permalink" do
      dir.join("agent.log").write("posted, no link")
      expect(run.permalink).to be_nil
    end

    it "returns the permalink in the log" do
      link = "https://acme.slack.com/archives/C123ABC/p1700000000123456"
      dir.join("agent.log").write("done\n#{link}\n")
      expect(run.permalink).to eq(link)
    end
  end

  describe "#start!" do
    let(:runner) { double("runner", start: 42) }
    let(:fresh_run) { described_class.for(tmp_root, 9, Time.zone.at(1_760_000_000)) }

    it "creates the dir, starts the run with the log path and options, and writes the pid" do
      fresh_run.start!(runner, "prompt", allowed_tools: %w[t], model: "haiku")

      expect(runner).to have_received(:start).with(
        fresh_run.to_s, "prompt", log_path: fresh_run.log_file.to_s, allowed_tools: %w[t], model: "haiku"
      )
      expect(fresh_run.pid_file.read).to eq("42")
    end

    it "writes no pid when the runner raises" do
      allow(runner).to receive(:start).and_raise(AiCli::CommandError, "boom")
      expect { fresh_run.start!(runner, "p") }.to raise_error(AiCli::CommandError)
      expect(fresh_run.pid_file).not_to exist
    end
  end

  describe "#running?" do
    let(:poller) { double("poller") }
    let(:fresh) { run.started_at + 1.minute }
    let(:stale) { run.started_at + 10.minutes }

    before { dir.join("pid").write("42") }

    it "is true when the pid is alive and the run is fresh" do
      allow(poller).to receive(:call).with(42).and_return(:running)
      expect(run.running?(poller, fresh)).to be(true)
    end

    it "is false when alive but stale" do
      allow(poller).to receive(:call).with(42).and_return(:running)
      expect(run.running?(poller, stale)).to be(false)
    end

    it "is false when the pid is dead" do
      allow(poller).to receive(:call).with(42).and_return([ :completed, nil ])
      expect(run.running?(poller, fresh)).to be(false)
    end

    it "is false without a pid file and does not poll" do
      dir.join("pid").delete
      allow(poller).to receive(:call)
      expect(run.running?(poller, fresh)).to be(false)
      expect(poller).not_to have_received(:call)
    end
  end
end
