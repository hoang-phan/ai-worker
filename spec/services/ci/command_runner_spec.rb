require "rails_helper"

RSpec.describe Ci::CommandRunner, type: :service do
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
