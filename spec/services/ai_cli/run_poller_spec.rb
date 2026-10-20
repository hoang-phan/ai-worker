require "rails_helper"
require "tmpdir"

RSpec.describe AiCli::RunPoller do
  let(:dir) { Dir.mktmpdir }
  let(:log_path) { File.join(dir, "run.log") }
  let(:started_at) { 1.minute.ago }
  let(:log_text) { "some output\n" }

  after { FileUtils.remove_entry(dir) }

  before do
    File.write(log_path, log_text)
    allow(AiCli::Runner).to receive(:tail_new_lines).and_return([ "", 42 ])
    allow(AiCli::Runner).to receive(:agent).and_return("claude")
    allow(Process).to receive(:kill)
  end

  def poller(**overrides)
    described_class.new(
      **{ pid: 123, log_path: log_path, log_offset: 0, started_at: started_at, log_tag: "workflow=1 stage=2", stale_after: 3.hours }.merge(overrides)
    )
  end

  def status(success)
    instance_double(Process::Status, success?: success)
  end

  it "returns :running and exposes the new log offset" do
    allow(AiCli::Runner).to receive(:poll).with(123).and_return(:running)
    p = poller

    expect(p.call).to eq(:running)
    expect(p.log_offset).to eq(42)
    expect(AiCli::Runner).to have_received(:tail_new_lines).with(log_path, from_offset: 0, log_tag: "workflow=1 stage=2")
    expect(Process).not_to have_received(:kill)
  end

  it "kills a stale running run and raises timed out" do
    allow(AiCli::Runner).to receive(:poll).and_return(:running)

    expect { poller(started_at: 4.hours.ago).call }
      .to raise_error(AiCli::CommandError, "claude timed out after #{3.hours.inspect} (pid=123)")
    expect(Process).to have_received(:kill).with("TERM", 123)
  end

  it "ignores a missing process when killing a stale run" do
    allow(AiCli::Runner).to receive(:poll).and_return(:running)
    allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

    expect { poller(started_at: 4.hours.ago).call }.to raise_error(AiCli::CommandError, /timed out/)
  end

  it "returns the full log when finished with a success status" do
    allow(AiCli::Runner).to receive(:poll).and_return([ :exited, status(true) ])

    expect(poller.call).to eq([ :finished, log_text ])
  end

  it "raises with the log text on a non-zero status" do
    allow(AiCli::Runner).to receive(:poll).and_return([ :exited, status(false) ])

    expect { poller.call }.to raise_error(AiCli::CommandError, "claude failed (pid=123): some output\n")
  end

  it "says 'no output' on failure with an empty log" do
    File.write(log_path, "")
    allow(AiCli::Runner).to receive(:poll).and_return([ :exited, status(false) ])

    expect { poller.call }.to raise_error(AiCli::CommandError, "claude failed (pid=123): no output")
  end

  context "with an unknown (nil) exit status" do
    before { allow(AiCli::Runner).to receive(:poll).and_return([ :exited, nil ]) }

    context "when the result event is a success" do
      let(:log_text) { %({"type":"result","is_error":false}\n) }

      it("finishes") { expect(poller.call).to eq([ :finished, log_text ]) }
    end

    context "when the result event is an error" do
      let(:log_text) { %({"type":"result","is_error":true}\n) }

      it "raises failed with the log" do
        expect { poller.call }.to raise_error(AiCli::CommandError, "claude failed (pid=123): #{log_text}")
      end
    end

    context "when there is no result event" do
      it "raises exit status unknown" do
        expect { poller.call }
          .to raise_error(AiCli::CommandError, "claude exit status unknown (pid=123), treating as failed")
      end
    end
  end
end
