require "rails_helper"

RSpec.describe AiCli::RunVerdict do
  def status(success)
    instance_double(Process::Status, success?: success)
  end

  def verdict(exit_status:, output: "some output\n")
    described_class.new(exit_status: exit_status, output: output, agent: "claude", pid: 123)
  end

  let(:success_event) { %({"type":"result","is_error":false,"result":"ok"}\n) }
  let(:error_event) { %({"type":"result","is_error":true,"result":"boom"}\n) }

  it "returns the output for a successful status" do
    expect(verdict(exit_status: status(true)).verify!).to eq("some output\n")
  end

  it "raises with the output for a non-zero status" do
    expect { verdict(exit_status: status(false)).verify! }
      .to raise_error(AiCli::CommandError, "claude failed (pid=123): some output\n")
  end

  it "raises with 'no output' for a non-zero status and empty output" do
    expect { verdict(exit_status: status(false), output: "").verify! }
      .to raise_error(AiCli::CommandError, "claude failed (pid=123): no output")
  end

  context "when the exit status is nil" do
    it "returns the output when the final result event is a success" do
      expect(verdict(exit_status: nil, output: success_event).verify!).to eq(success_event)
    end

    it "raises failed when the final result event is an error" do
      expect { verdict(exit_status: nil, output: error_event).verify! }
        .to raise_error(AiCli::CommandError, "claude failed (pid=123): #{error_event}")
    end

    it "raises exit status unknown when there is no final result event" do
      expect { verdict(exit_status: nil).verify! }
        .to raise_error(AiCli::CommandError, "claude exit status unknown (pid=123), treating as failed")
    end
  end
end
