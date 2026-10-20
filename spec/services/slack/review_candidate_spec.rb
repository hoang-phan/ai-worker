require "rails_helper"

RSpec.describe Slack::ReviewCandidate do
  describe ".skip_reason" do
    def reason(state: "OPEN", author: "someone", login: "me")
      described_class.skip_reason(info: { "state" => state, "author" => author }, current_login: login)
    end

    it "is nil for an open PR by someone else" do
      expect(reason).to be_nil
    end

    it "returns the downcased state for merged and closed PRs" do
      expect(reason(state: "MERGED")).to eq("merged")
      expect(reason(state: "CLOSED")).to eq("closed")
    end

    it "reports own PR when the author is the current login, ignoring case" do
      expect(reason(author: "Me")).to eq("own PR")
    end

    it "prefers the state over the author" do
      expect(reason(state: "MERGED", author: "me")).to eq("merged")
    end
  end

  describe ".own_repo?" do
    it "matches the repo" do
      expect(described_class.own_repo?("https://github.com/acme/widgets/pull/1", "acme/widgets")).to be true
    end

    it "matches case-insensitively" do
      expect(described_class.own_repo?("https://github.com/Acme/Widgets/pull/1", "acme/widgets")).to be true
    end

    it "is false for another repo" do
      expect(described_class.own_repo?("https://github.com/acme/other/pull/1", "acme/widgets")).to be false
    end

    it "is falsy for malformed URLs" do
      expect(described_class.own_repo?("https://github.com/acme/widgets/issues/1", "acme/widgets")).to be_falsy
      expect(described_class.own_repo?("not a url", "acme/widgets")).to be_falsy
    end
  end
end
