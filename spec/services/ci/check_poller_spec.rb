require "rails_helper"

RSpec.describe Ci::CheckPoller, type: :service do
  let(:runner) { double("runner") }
  let(:kill) { double("kill", call: nil) }

  def poller(started_at: Time.current)
    described_class.new(pid: 42, log_offset: 0, started_at: started_at, stale_after: 3.hours, runner: runner, kill: kill)
  end

  it "is :running while the process lives" do
    allow(runner).to receive(:poll).with(42).and_return(:running)
    expect(poller.call).to eq :running
  end

  it "reports a failing exit status as a result, not an error" do
    status = instance_double(Process::Status, success?: false, exitstatus: 2)
    allow(runner).to receive(:poll).and_return([ :completed, status ])
    expect(poller.call).to eq [ :finished, 2 ]
  end

  it "reports success as 0" do
    allow(runner).to receive(:poll).and_return([ :completed, instance_double(Process::Status, success?: true) ])
    expect(poller.call).to eq [ :finished, 0 ]
  end

  it "raises when the status is unknown" do
    allow(runner).to receive(:poll).and_return([ :completed, nil ])
    expect { poller.call }.to raise_error(AiCli::CommandError, /unknown/)
  end

  it "kills a stale run and raises" do
    allow(runner).to receive(:poll).and_return(:running)
    expect { poller(started_at: 4.hours.ago).call }.to raise_error(AiCli::CommandError, /timed out/)
    expect(kill).to have_received(:call).with("TERM", -42)
  end

  it "ignores a missing process when killing a stale run" do
    allow(runner).to receive(:poll).and_return(:running)
    allow(kill).to receive(:call).and_raise(Errno::ESRCH)
    expect { poller(started_at: 4.hours.ago).call }.to raise_error(AiCli::CommandError, /timed out/)
  end
end
