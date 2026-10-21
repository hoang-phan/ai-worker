require "rails_helper"

RSpec.describe Workflows::Variables do
  describe ".parse" do
    {
      "simple pair" => [ "A=1", { "A" => "1" } ],
      "blank lines skipped" => [ "A=1\n\n   \nB=2\n", { "A" => "1", "B" => "2" } ],
      "missing '=' gives empty value" => [ "FLAG", { "FLAG" => "" } ],
      "value containing '='" => [ "URL=http://x?a=b=c", { "URL" => "http://x?a=b=c" } ],
      "lowercase name upcased" => [ "channel=dev", { "CHANNEL" => "dev" } ],
      "whitespace trimmed" => [ "  name  =  spaced value  \r\n", { "NAME" => "spaced value" } ],
      "line without a name dropped" => [ "=oops\nA=1", { "A" => "1" } ],
      "\\n becomes a newline" => [ "NOTE=a\\nb", { "NOTE" => "a\nb" } ],
      "nil text" => [ nil, {} ]
    }.each do |label, (text, expected)|
      it label do
        expect(described_class.parse(text)).to eq(expected)
      end
    end
  end

  describe ".to_text" do
    it "writes one NAME=value per line" do
      expect(described_class.to_text("A" => "1", "B" => "x=y")).to eq("A=1\nB=x=y")
    end

    it "escapes newlines and stringifies values" do
      expect(described_class.to_text("A" => "l1\nl2", "N" => 5, "Z" => nil)).to eq("A=l1\\nl2\nN=5\nZ=")
    end

    it "is empty for an empty hash" do
      expect(described_class.to_text({})).to eq("")
    end

    it "round-trips multi-line values" do
      vars = { "A" => "one\ntwo\nthree", "B" => "x=y" }
      expect(described_class.parse(described_class.to_text(vars))).to eq(vars)
    end
  end

  describe ".input_only" do
    let(:variables) { { "CHANNEL" => "dev", "PR_URL" => "u", "NOTES" => "n" } }

    {
      "no outputs" => [ [], %w[CHANNEL PR_URL NOTES] ],
      "VAR: line excluded" => [ [ "done\nVAR: PR_URL=http://x" ], %w[CHANNEL NOTES] ],
      "VAR_BEGIN/VAR_END block excluded" => [ [ "VAR_BEGIN: notes\nl1\nl2\nVAR_END" ], %w[CHANNEL PR_URL] ],
      "both, across outputs" => [ [ "VAR: pr_url=1", "VAR_BEGIN: NOTES\nx\nVAR_END" ], %w[CHANNEL] ],
      "output without variables" => [ [ "just text", nil ], %w[CHANNEL PR_URL NOTES] ]
    }.each do |label, (outputs, expected_keys)|
      it label do
        expect(described_class.input_only(variables, outputs).keys).to match_array(expected_keys)
      end
    end
  end
end
