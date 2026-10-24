require "rails_helper"

RSpec.describe Slack::PingCollector do
  let(:root) { Pathname(make_tmpdir("ping-collector-spec")) }
  let(:poller) { double("poller", call: [ :completed, nil ]) }
  let(:collector) { described_class.new(root: root, poller: poller) }
  let(:workflow) { instance_double(Workflow, id: 7, slack_review_thread_ts: nil) }
  let(:workflow_dir) { root.join("7") }
  let(:link) { "https://ws.slack.com/archives/C123/p1760000000123456" }

  def ping(started_at: Time.current.to_i, pid: 42, log: nil)
    path = workflow_dir.join(started_at.to_s)
    FileUtils.mkdir_p(path)
    path.join("pid").write(pid) if pid
    path.join("agent.log").write(log) if log
    path
  end

  it "saves the permalink and cleans up once the run finished" do
    ping(log: "Posted.\n#{link}\n")
    expect(workflow).to receive(:update!).with(slack_review_thread_ts: link)
    expect(collector.collect(workflow)).to be(false)
    expect(workflow_dir).not_to exist
  end

  it "keeps running = true and leaves a fresh running dir alone" do
    path = ping(log: "")
    allow(poller).to receive(:call).with(42).and_return(:running)
    expect(workflow).not_to receive(:update!)
    expect(collector.collect(workflow)).to be(true)
    expect(path).to exist
  end

  it "treats a stale running dir as finished" do
    path = ping(started_at: 10.minutes.ago.to_i, log: link)
    allow(poller).to receive(:call).and_return(:running)
    expect(workflow).to receive(:update!).with(slack_review_thread_ts: link)
    expect(collector.collect(workflow)).to be(false)
    expect(path).not_to exist
  end

  it "logs and keeps a dir without a permalink" do
    path = ping(log: "could not post")
    expect(Rails.logger).to receive(:warn).with(/no permalink/)
    expect(workflow).not_to receive(:update!)
    expect(collector.collect(workflow)).to be(false)
    expect(path).to exist
    expect(workflow_dir).to exist
  end

  it "does not overwrite an existing thread but still cleans up" do
    path = ping(log: link)
    allow(workflow).to receive(:slack_review_thread_ts).and_return("existing")
    expect(workflow).not_to receive(:update!)
    collector.collect(workflow)
    expect(path).not_to exist
  end

  it "keeps the workflow dir while a run is going" do
    ping(started_at: 1.minute.ago.to_i, pid: 1, log: link)
    ping(pid: 2, log: "")
    allow(poller).to receive(:call).with(1).and_return([ :completed, nil ])
    allow(poller).to receive(:call).with(2).and_return(:running)
    allow(workflow).to receive(:update!)
    expect(collector.collect(workflow)).to be(true)
    expect(workflow_dir).to exist
  end

  it "removes the workflow dir when it is empty and nothing runs" do
    FileUtils.mkdir_p(workflow_dir)
    expect(collector.collect(workflow)).to be(false)
    expect(workflow_dir).not_to exist
  end

  it "keeps the workflow dir when a finished ping without a permalink remains" do
    ping(log: "nothing")
    allow(Rails.logger).to receive(:warn)
    collector.collect(workflow)
    expect(workflow_dir).to exist
  end

  it "keeps a fresh running dir even when it already has a permalink" do
    path = ping(log: link)
    allow(poller).to receive(:call).with(42).and_return(:running)
    expect(workflow).not_to receive(:update!)
    expect(collector.collect(workflow)).to be(true)
    expect(path).to exist
  end

  it "returns false on Errno::ENOENT" do
    ping(log: link)
    allow(workflow).to receive(:update!).and_raise(Errno::ENOENT)
    expect(collector.collect(workflow)).to be(false)
  end

  it "lists pending workflow ids" do
    FileUtils.mkdir_p(root.join("3"))
    expect(collector.pending_workflow_ids).to eq([ 3 ])
  end

  describe "#collect_all" do
    it "removes the dir of a workflow that is gone" do
      ping
      collector.collect_all(find_workflow: ->(_id) { nil })
      expect(workflow_dir).not_to exist
    end

    it "collects an existing workflow" do
      ping(log: link)
      expect(workflow).to receive(:update!).with(slack_review_thread_ts: link)
      collector.collect_all(find_workflow: ->(id) { id == 7 ? workflow : nil })
      expect(workflow_dir).not_to exist
    end

    it "keeps a dir that is still running" do
      path = ping(log: "")
      allow(poller).to receive(:call).with(42).and_return(:running)
      expect(workflow).not_to receive(:update!)
      collector.collect_all(find_workflow: ->(_id) { workflow })
      expect(path).to exist
    end
  end
end
