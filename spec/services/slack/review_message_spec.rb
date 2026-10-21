require "rails_helper"

RSpec.describe Slack::ReviewMessage do
  let(:pr_url) { "https://github.com/o/r/pull/1" }
  let(:ids) { { "bob" => "U1" } }
  let(:reviewers) { %w[bob amy] }

  def build(**opts)
    described_class.new(pr_url: pr_url, label: "ENG-1 Fix", reviewers: reviewers, slack_id_for: ->(login) { ids[login] }, **opts)
  end

  describe "#text" do
    it "tags mapped reviewers, falls back to @login for unmapped ones and links the PR" do
      expect(build.text).to eq(":eyes: <@U1> @amy please review [ENG-1 Fix](https://github.com/o/r/pull/1)")
    end

    it "escapes [] to () in the label" do
      text = described_class.new(pr_url: pr_url, label: "ENG-1 [x]", reviewers: [], slack_id_for: ->(_) { nil }).text
      expect(text).to eq(":eyes: please review [ENG-1 (x)](https://github.com/o/r/pull/1)")
    end

    it "marks a re-request without a Fixed section when nothing is fixed" do
      expect(build(again: true).text).to eq(":eyes: <@U1> @amy changes pushed, please re-review [ENG-1 Fix](https://github.com/o/r/pull/1)")
    end

    it "adds the stripped Fixed section to a re-request" do
      expect(build(again: true, fixed: "\n- null check\n").text).to eq(
        ":eyes: <@U1> @amy changes pushed, please re-review [ENG-1 Fix](https://github.com/o/r/pull/1)\nFixed:\n- null check"
      )
    end

    it "ignores fixed on a first request" do
      expect(build(fixed: "x").text).not_to include("Fixed")
    end
  end

  describe "#prompt" do
    it "posts the message to the channel as a new message" do
      prompt = build.prompt(channel: "C123")
      expect(prompt).to include("Slack channel C123 using the Slack MCP send-message tool (channel_id: C123).")
      expect(prompt).not_to include("thread_ts")
      expect(prompt).to include("<message>\n#{build.text}\n</message>")
    end

    it "replies in the thread when thread_ts is given" do
      expect(build.prompt(channel: "C123", thread_ts: "1.2")).to include("(channel_id: C123, thread_ts: 1.2).")
    end
  end
end
