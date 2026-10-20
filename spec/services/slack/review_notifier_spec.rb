require "rails_helper"

RSpec.describe Slack::ReviewNotifier do
  let(:channel) { "C0123456789" }
  let(:user_map) { "alice=U111\nbob: U222" }
  let(:project) { Project.new(slack_review_channel: channel, slack_user_map: user_map) }
  let(:client) { double("Slack::WebClient") }
  let(:notifier) { described_class.new(project, client: client) }
  let(:pr_url) { "https://github.com/o/r/pull/1" }
  let(:token) { "xoxb-fake-token" }

  def stub_token(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SLACK_BOT_TOKEN").and_return(value)
  end

  before { stub_token(token) }

  describe "#message" do
    it "asks for a first review" do
      text = notifier.message(pr_url: pr_url, label: "ENG-1 Fix thing", reviewers: %w[alice])
      expect(text).to eq ":eyes: <@U111> please review <#{pr_url}|ENG-1 Fix thing>"
    end

    it "marks a re-request without a fixed summary" do
      text = notifier.message(pr_url: pr_url, label: "ENG-1", reviewers: %w[alice], again: true)
      expect(text).to eq ":eyes: <@U111> changes pushed, please re-review <#{pr_url}|ENG-1>"
    end

    it "appends the fixed summary on a re-request" do
      text = notifier.message(pr_url: pr_url, label: "ENG-1", reviewers: %w[alice], again: true, fixed: "  Handled nil case \n")
      expect(text).to eq ":eyes: <@U111> changes pushed, please re-review <#{pr_url}|ENG-1>\nFixed:\nHandled nil case"
    end

    it "ignores a blank fixed summary" do
      text = notifier.message(pr_url: pr_url, label: "ENG-1", reviewers: %w[alice], again: true, fixed: "  ")
      expect(text).not_to include("Fixed:")
    end

    it "maps reviewers to Slack users and falls back to @login" do
      text = notifier.message(pr_url: pr_url, label: "ENG-1", reviewers: %w[alice @Bob carol])
      expect(text).to eq ":eyes: <@U111> <@U222> @carol please review <#{pr_url}|ENG-1>"
    end

    it "escapes & < > | in the label and fixed summary" do
      text = notifier.message(pr_url: pr_url, label: "A & B <c> | d", reviewers: [], again: true, fixed: "x < y & z > w | v")
      expect(text).to include("<#{pr_url}|A &amp; B &lt;c&gt; ¦ d>")
      expect(text).to include("Fixed:\nx &lt; y &amp; z &gt; w ¦ v")
    end
  end

  describe "#enabled? / #blockers" do
    it "is enabled with a channel and token" do
      expect(notifier).to be_enabled
      expect(notifier.blockers).to be_empty
    end

    it "is blocked without a token" do
      stub_token(nil)
      expect(notifier).not_to be_enabled
      expect(notifier.blockers).to eq [ "SLACK_BOT_TOKEN is not set" ]
    end

    it "treats an empty token as unset" do
      stub_token("")
      expect(notifier).not_to be_enabled
    end

    it "is blocked without a channel" do
      project.slack_review_channel = ""
      expect(notifier).not_to be_enabled
      expect(notifier.blockers).to eq [ "Slack channel is not set" ]
    end

    it "lists both blockers" do
      stub_token(nil)
      project.slack_review_channel = nil
      expect(notifier.blockers.size).to eq 2
    end
  end

  describe "#notify!" do
    it "posts the message to the channel and returns the ts" do
      expect(client).to receive(:post_message)
        .with(channel: channel, text: ":eyes: <@U111> please review <#{pr_url}|ENG-1>", thread_ts: nil)
        .and_return("ok" => true, "ts" => "1760000000.000100")
      expect(notifier.notify!(pr_url: pr_url, label: "ENG-1", reviewers: %w[alice])).to eq "1760000000.000100"
    end

    it "passes thread_ts for replies" do
      expect(client).to receive(:post_message)
        .with(hash_including(channel: channel, thread_ts: "1760000000.000100"))
        .and_return("ts" => "1760000000.000200")
      result = notifier.notify!(pr_url: pr_url, label: "ENG-1", reviewers: %w[alice], again: true, thread_ts: "1760000000.000100")
      expect(result).to eq "1760000000.000200"
    end

    it "raises NotifyError when blocked, without calling the client" do
      stub_token(nil)
      expect(client).not_to receive(:post_message)
      expect { notifier.notify!(pr_url: pr_url, label: "ENG-1", reviewers: []) }
        .to raise_error(Slack::NotifyError, /SLACK_BOT_TOKEN is not set/)
    end
  end

  it "defaults to a Slack::WebClient built with the token" do
    web_client = instance_double(Slack::WebClient, post_message: { "ts" => "1.2" })
    expect(Slack::WebClient).to receive(:new).with(token).and_return(web_client)
    expect(described_class.new(project).notify!(pr_url: pr_url, label: "x", reviewers: [])).to eq "1.2"
  end
end
