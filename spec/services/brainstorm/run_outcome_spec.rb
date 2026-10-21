require "rails_helper"

RSpec.describe Brainstorm::RunOutcome do
  let(:tmpdir) { Pathname(Dir.mktmpdir("run-outcome-spec")) }
  let(:log_path) { tmpdir.join("agent.log") }
  let(:retried) { false }
  let(:aborted) { '{"type":"result","subtype":"error_during_execution","terminal_reason":"aborted_streaming"}' }

  subject(:outcome) { described_class.new(log_path: log_path, retried: retried) }

  after { FileUtils.remove_entry(tmpdir) }

  context "without a log file" do
    it "has no event, does not retry and says so" do
      expect(outcome.event).to be_nil
      expect(outcome.retry?).to be(false)
      expect(outcome.failure_reason).to eq("no result event in the log")
    end
  end

  context "with a log without a result event" do
    before { log_path.write(%({"type":"assistant"}\n{"type":"system"}\n)) }

    it "has no event" do
      expect(outcome.event).to be_nil
      expect(outcome.retry?).to be(false)
      expect(outcome.failure_reason).to eq("no result event in the log")
    end
  end

  context "with a malformed result line" do
    before { log_path.write(%({"type":"result","subtype":\n)) }

    it "treats it as no event" do
      expect(outcome.event).to be_nil
      expect(outcome.failure_reason).to eq("no result event in the log")
    end
  end

  context "with several result events" do
    before do
      log_path.write(%({"type":"result","subtype":"first"}\n{"type":"assistant"}\n{"type":"result","subtype":"last"}\n{"type":"assistant"}\n))
    end

    it "uses the last one" do
      expect(outcome.event["subtype"]).to eq("last")
      expect(outcome.failure_reason).to eq("last")
    end
  end

  context "when the stream was aborted" do
    before { log_path.write("#{aborted}\n") }

    it "retries when not retried yet" do
      expect(outcome.retry?).to be(true)
      expect(outcome.failure_reason).to eq("error_during_execution/aborted_streaming")
    end

    context "and the retry was already used" do
      let(:retried) { true }

      it "does not retry" do
        expect(outcome.retry?).to be(false)
      end
    end
  end

  describe "#failure_reason" do
    it "joins subtype and terminal_reason" do
      log_path.write(%({"type":"result","subtype":"error_max_turns","terminal_reason":"max_turns"}\n))
      expect(outcome.failure_reason).to eq("error_max_turns/max_turns")
      expect(outcome.retry?).to be(false)
    end

    it "uses only the subtype when there is no terminal_reason" do
      log_path.write(%({"type":"result","subtype":"error_during_execution"}\n))
      expect(outcome.failure_reason).to eq("error_during_execution")
    end

    it "uses only the terminal_reason when there is no subtype" do
      log_path.write(%({"type":"result","terminal_reason":"aborted_tools"}\n))
      expect(outcome.failure_reason).to eq("aborted_tools")
    end

    it "is empty when the event has neither" do
      log_path.write(%({"type":"result"}\n))
      expect(outcome.failure_reason).to eq("")
    end
  end
end
