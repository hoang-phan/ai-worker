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
end
