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
    allow_any_instance_of(AiCli::LogTail).to receive(:read_from).and_return([ "", 42 ])
  end

  let(:runner) { double("runner", agent: "claude") }
  let(:kill) { double("kill", call: nil) }

  def poller(**overrides)
    described_class.new(
      **{ pid: 123, log_path: log_path, log_offset: 0, started_at: started_at, log_tag: "workflow=1 stage=2", stale_after: 3.hours, runner: runner, kill: kill }.merge(overrides)
    )
  end

  def status(success)
    instance_double(Process::Status, success?: success)
  end

  it "returns :running and exposes the new log offset" do
    allow(runner).to receive(:poll).with(123).and_return(:running)
    p = poller

    expect(p.call).to eq(:running)
    expect(p.log_offset).to eq(42)
    expect(kill).not_to have_received(:call)
  end

  it "names the run's own provider rather than the app-wide agent in errors" do
    allow(runner).to receive(:poll).and_return(:running)

    expect { poller(started_at: 4.hours.ago, provider: "codex").call }
      .to raise_error(AiCli::CommandError, "codex timed out after #{3.hours.inspect} (pid=123)")
  end

  it "judges a lost exit status by the run's own provider" do
    allow(runner).to receive(:poll).and_return([ :completed, nil ])
    allow_any_instance_of(AiCli::LogTail).to receive(:full).and_return(%({"type":"result","is_error":false,"result":"ok"}\n))

    expect { poller(provider: "codex").call }.to raise_error(AiCli::CommandError, /codex exit status unknown/)
    expect(poller(provider: "").call.first).to eq :finished
  end

  it "kills a stale running run and raises timed out" do
    allow(runner).to receive(:poll).and_return(:running)

    expect { poller(started_at: 4.hours.ago).call }
      .to raise_error(AiCli::CommandError, "claude timed out after #{3.hours.inspect} (pid=123)")
    expect(kill).to have_received(:call).with("TERM", 123)
  end

  it "ignores a missing process when killing a stale run" do
    allow(runner).to receive(:poll).and_return(:running)
    allow(kill).to receive(:call).and_raise(Errno::ESRCH)

    expect { poller(started_at: 4.hours.ago).call }.to raise_error(AiCli::CommandError, /timed out/)
  end

  it "returns the full log when finished with a success status" do
    allow(runner).to receive(:poll).and_return([ :exited, status(true) ])

    expect(poller.call).to eq([ :finished, log_text ])
  end

  it "raises with the log text on a non-zero status" do
    allow(runner).to receive(:poll).and_return([ :exited, status(false) ])

    expect { poller.call }.to raise_error(AiCli::CommandError, "claude failed (pid=123): some output\n")
  end

  it "says 'no output' on failure with an empty log" do
    File.write(log_path, "")
    allow(runner).to receive(:poll).and_return([ :exited, status(false) ])

    expect { poller.call }.to raise_error(AiCli::CommandError, "claude failed (pid=123): no output")
  end

  context "with an unknown (nil) exit status" do
    before { allow(runner).to receive(:poll).and_return([ :exited, nil ]) }

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
