require "rails_helper"

RSpec.describe AiCli::Output do
  def output(text) = described_class.new(text)

  describe "#variables" do
    it "reads single-line variables and upcases names" do
      expect(output("noise\n  VAR: version=2.1\nVAR: Other=  x y ").variables).to eq("VERSION" => "2.1", "OTHER" => "x y")
    end

    it "reads multi-line blocks" do
      text = "VAR_BEGIN: notes\nline one\nline two\nVAR_END\nVAR: A=1"
      expect(output(text).variables).to eq("NOTES" => "line one\nline two", "A" => "1")
    end

    it "does not treat VAR lines inside a block as variables" do
      expect(output("VAR_BEGIN: x\nVAR: Y=2\nVAR_END").variables).to eq("X" => "VAR: Y=2")
    end

    it "is empty for nil or no markers" do
      expect(output(nil).variables).to eq({})
    end
  end

  describe "#jira_result" do
    it("returns UAT") { expect(output("JIRA_RESULT: UAT").jira_result).to eq("UAT") }
    it("is case-insensitive") { expect(output("jira_result: releaseable").jira_result).to eq("releaseable") }
    it("uses the first match") { expect(output("JIRA_RESULT: UAT\nJIRA_RESULT: RELEASEABLE").jira_result).to eq("UAT") }
    it("is nil when missing") { expect(output("nothing").jira_result).to be_nil }
    it("is nil for other values") { expect(output("JIRA_RESULT: DONE").jira_result).to be_nil }
  end

  describe "#uat_result" do
    it("returns the verdict") { expect(output("UAT_RESULT: BLOCKED").uat_result).to eq("BLOCKED") }
    it("is case-insensitive") { expect(output("uat_result: passed").uat_result).to eq("passed") }
    it("uses the first match") { expect(output("UAT_RESULT: PASSED\nUAT_RESULT: FAILED").uat_result).to eq("PASSED") }
    it("is nil when missing") { expect(output("x").uat_result).to be_nil }
  end

  describe "#local_test_result" do
    it("returns the verdict") { expect(output("LOCAL_TEST_RESULT: FAILED").local_test_result).to eq("FAILED") }
    it("is case-insensitive") { expect(output("local_test_result: passed").local_test_result).to eq("passed") }
    it("uses the first match") { expect(output("LOCAL_TEST_RESULT: PASSED\nLOCAL_TEST_RESULT: FAILED").local_test_result).to eq("PASSED") }
    it("is nil when missing") { expect(output(nil).local_test_result).to be_nil }
  end

  describe "#retest_requested?" do
    it("is true when absent") { expect(output("nothing").retest_requested?).to be true }
    it("is true for YES") { expect(output("LOCAL_RETEST: YES").retest_requested?).to be true }
    it("is false for NO") { expect(output("LOCAL_RETEST: no").retest_requested?).to be false }
    it("uses the last line") { expect(output("LOCAL_RETEST: YES\nLOCAL_RETEST: NO").retest_requested?).to be false }
  end

  describe "#local_test_feedback_block" do
    it "returns the last block (prompt echo first)" do
      text = "LOCAL_TEST_FEEDBACK_BEGIN\n<example>\nLOCAL_TEST_FEEDBACK_END\nLOCAL_TEST_FEEDBACK_BEGIN\n real failure \nmore\nLOCAL_TEST_FEEDBACK_END"
      expect(output(text).local_test_feedback_block).to eq("real failure \nmore")
    end

    it("is nil when missing") { expect(output("x").local_test_feedback_block).to be_nil }

    it "is nil for an empty block" do
      expect(output("LOCAL_TEST_FEEDBACK_BEGIN\n \nLOCAL_TEST_FEEDBACK_END").local_test_feedback_block).to be_nil
    end
  end

  describe "#fixed_summary" do
    it "returns the last block" do
      text = "FIXED_SUMMARY_BEGIN\nexample\nFIXED_SUMMARY_END\nFIXED_SUMMARY_BEGIN\n- fixed a\n- fixed b\nFIXED_SUMMARY_END"
      expect(output(text).fixed_summary).to eq("- fixed a\n- fixed b")
    end

    it("is nil when missing") { expect(output("x").fixed_summary).to be_nil }
  end

  describe "#follow_ups" do
    let(:block) { %(FOLLOW_UPS_BEGIN\n[{"summary":"Fix X","task":"Do X in a.rb, verify with rspec"}]\nFOLLOW_UPS_END) }

    it "parses the block" do
      expect(output("done\n#{block}\n").follow_ups).to eq([ { "summary" => "Fix X", "task" => "Do X in a.rb, verify with rspec" } ])
    end

    it "uses the last block when the prompt's example was echoed" do
      echoed = %(FOLLOW_UPS_BEGIN\n[{"summary":"Example","task":"Example task"}]\nFOLLOW_UPS_END\n)
      expect(output("#{echoed}work\n#{block}").follow_ups.map { |row| row["summary"] }).to eq([ "Fix X" ])
    end

    it "cleans rows" do
      long = "a" * 300
      text = %(FOLLOW_UPS_BEGIN\n[{"summary":"#{long}","task":"t"},{"summary":"","task":"t"},"x"]\nFOLLOW_UPS_END)
      expect(output(text).follow_ups.map { |row| row["summary"].length }).to eq([ Workflow::SUMMARY_LENGTH ])
    end

    it("is empty for invalid JSON") { expect(output("FOLLOW_UPS_BEGIN\nnot json\nFOLLOW_UPS_END").follow_ups).to eq([]) }
    it("is empty for a non-array") { expect(output(%(FOLLOW_UPS_BEGIN\n{"a":1}\nFOLLOW_UPS_END)).follow_ups).to eq([]) }
    it("is empty when missing") { expect(output("x").follow_ups).to eq([]) }
  end

  describe "#lessons" do
    it "returns the lines of the last block without bullets or blank lines" do
      text = "LESSONS_BEGIN\nexample\nLESSONS_END\nLESSONS_BEGIN\n- Use partial A\n\n  - Prefer B  \nplain C\nLESSONS_END\nLOCAL_RETEST: NO"
      expect(output(text).lessons).to eq([ "Use partial A", "Prefer B", "plain C" ])
    end

    it("is empty when missing") { expect(output("x").lessons).to eq([]) }
    it("is empty for an empty block") { expect(output("LESSONS_BEGIN\nLESSONS_END").lessons).to eq([]) }
  end

  describe "#posted?" do
    it("matches a POSTED line") { expect(output("done\nPOSTED\n").posted?).to be true }
    it("allows surrounding whitespace") { expect(output("done\n   POSTED  \n").posted?).to be true }
    it("rejects POSTED inside a sentence") { expect(output("not POSTED yet").posted?).to be false }
    it("is false when missing") { expect(output(nil).posted?).to be false }
  end

  describe "claude result forwarding" do
    it("forwards #final_outcome") { expect(output(%({"type":"result","is_error":true})).final_outcome).to eq(:error) }
    it("forwards #result_event") { expect(output(%({"type":"result","subtype":"x"})).result_event).to eq({ "type" => "result", "subtype" => "x" }) }
    it("is nil for nil") { expect(output(nil).final_outcome).to be_nil }
  end
end

RSpec.describe AiCli::Output, "#ci_verdict" do
  it "takes the last verdict, upcased" do
    expect(described_class.new("CI_VERDICT: PASSED\n...\nci_verdict: failed").ci_verdict).to eq "FAILED"
  end

  it "is nil without one" do
    expect(described_class.new("nothing").ci_verdict).to be_nil
  end
end
