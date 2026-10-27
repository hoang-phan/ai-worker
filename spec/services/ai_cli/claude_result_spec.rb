require "rails_helper"

RSpec.describe AiCli::ClaudeResult do
  def result(text) = described_class.new(text)

  describe "#final_outcome" do
    it("is :success for a non-error result event") { expect(result(%({"type":"result","is_error":false})).final_outcome).to eq(:success) }
    it("is :error for an error result event") { expect(result(%({"type":"result","is_error":true})).final_outcome).to eq(:error) }
    it("is nil without a result event") { expect(result(%(plain\n{"type":"assistant"})).final_outcome).to be_nil }
    it("is nil for nil") { expect(result(nil).final_outcome).to be_nil }

    it "uses the last result event and skips malformed JSON lines" do
      text = %({"type":"result","is_error":true}\n{"type":"result","is_error":false}\n{not json\n)
      expect(result(text).final_outcome).to eq(:success)
    end
  end

  describe "#result_event" do
    it("is nil without a result event") { expect(result(%(plain\n{"type":"assistant"})).result_event).to be_nil }
    it("returns a single result event") { expect(result(%({"type":"result","is_error":false})).result_event).to eq({ "type" => "result", "is_error" => false }) }

    it "returns the last of several result events" do
      text = %({"type":"result","subtype":"first"}\n{"type":"result","subtype":"last"}\n)
      expect(result(text).result_event).to eq({ "type" => "result", "subtype" => "last" })
    end

    it "skips an invalid JSON line" do
      text = %({"type":"result","subtype":"valid"}\n{not json\n)
      expect(result(text).result_event).to eq({ "type" => "result", "subtype" => "valid" })
    end

    it "ignores non-result JSON" do
      text = %({"type":"result","subtype":"valid"}\n{"type":"assistant"}\n)
      expect(result(text).result_event).to eq({ "type" => "result", "subtype" => "valid" })
    end
  end

  it("ignores lines that do not start with {") do
    expect(result(%( {"type":"result"})).result_event).to be_nil
  end

  it("treats a missing is_error as success") do
    expect(result(%({"type":"result"})).final_outcome).to eq(:success)
  end
end
