require "rails_helper"

RSpec.describe "CI check run", type: :service do
  describe Ci::CommandRunner do
    it "runs the command detached in the directory and logs its output" do
      Dir.mktmpdir do |dir|
        log = File.join(dir, "logs", "ci.log")
        pid = described_class.start(dir, "pwd; echo out; echo err >&2; exit 3", log_path: log)
        _pid, status = Process.wait2(pid)

        expect(status.exitstatus).to eq 3
        expect(File.read(log)).to include(File.realpath(dir), "out", "err")
      end
    end
  end

  describe Ci::CheckPoller do
    def poller(started_at: Time.current) = described_class.new(pid: 42, log_offset: 0, started_at: started_at, stale_after: 3.hours)

    it "is :running while the process lives" do
      allow(AiCli::Runner).to receive(:poll).with(42).and_return(:running)
      expect(poller.call).to eq :running
    end

    it "reports a failing exit status as a result, not an error" do
      status = instance_double(Process::Status, success?: false, exitstatus: 2)
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, status ])
      expect(poller.call).to eq [ :finished, 2 ]
    end

    it "reports success as 0" do
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, instance_double(Process::Status, success?: true) ])
      expect(poller.call).to eq [ :finished, 0 ]
    end

    it "raises when the status is unknown" do
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, nil ])
      expect { poller.call }.to raise_error(AiCli::CommandError, /unknown/)
    end

    it "kills a stale run and raises" do
      allow(AiCli::Runner).to receive(:poll).and_return(:running)
      allow(Process).to receive(:kill)
      expect { poller(started_at: 4.hours.ago).call }.to raise_error(AiCli::CommandError, /timed out/)
      expect(Process).to have_received(:kill).with("TERM", -42)
    end
  end
end
