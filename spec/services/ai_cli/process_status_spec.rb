require "rails_helper"

RSpec.describe AiCli::ProcessStatus do
  let(:process) { double("process") }
  let(:pid) { 4242 }

  subject(:status_for) { described_class.new(process: process).call(pid) }

  it "returns [:completed, status] when wait2 reaps the process" do
    status = instance_double(Process::Status)
    allow(process).to receive(:wait2).with(pid, Process::WNOHANG).and_return([ pid, status ])

    expect(status_for).to eq([ :completed, status ])
  end

  it "returns :running when wait2 returns nil" do
    allow(process).to receive(:wait2).with(pid, Process::WNOHANG).and_return(nil)

    expect(status_for).to eq(:running)
  end

  context "when wait2 raises ECHILD" do
    before { allow(process).to receive(:wait2).and_raise(Errno::ECHILD) }

    it "returns :running if the pid is still alive" do
      allow(process).to receive(:getpgid).with(pid).and_return(pid)

      expect(status_for).to eq(:running)
    end

    it "returns [:completed, nil] if the pid is gone" do
      allow(process).to receive(:getpgid).with(pid).and_raise(Errno::ESRCH)

      expect(status_for).to eq([ :completed, nil ])
    end
  end

  it "returns [:completed, nil] when wait2 raises ESRCH" do
    allow(process).to receive(:wait2).and_raise(Errno::ESRCH)

    expect(status_for).to eq([ :completed, nil ])
  end
end
