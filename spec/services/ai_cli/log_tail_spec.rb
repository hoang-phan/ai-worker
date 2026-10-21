require "rails_helper"
require "tmpdir"

RSpec.describe AiCli::LogTail do
  let(:dir) { Dir.mktmpdir }
  let(:log_path) { File.join(dir, "run.log") }
  let(:tail) { described_class.new(log_path: log_path, log_tag: "workflow=1 stage=2") }

  after { FileUtils.remove_entry(dir) }

  describe "#read_from" do
    it "returns empty content and the same offset when the file is missing" do
      expect(tail.read_from(7)).to eq([ "", 7 ])
    end

    it "advances the offset by bytesize with multibyte content" do
      File.write(log_path, "héllo ✓\n")

      content, offset = tail.read_from(0)

      expect(content.bytesize).to eq(11)
      expect(offset).to eq(11)
      expect(tail.read_from(offset)).to eq([ "", 11 ])
    end

    it "returns only what was written since the offset" do
      File.write(log_path, "one\n")
      _content, offset = tail.read_from(0)
      File.write(log_path, "two\n", mode: "a")

      expect(tail.read_from(offset)).to eq([ "two\n", 8 ])
    end

    it "logs each line with the tag" do
      File.write(log_path, "one\ntwo\n")
      allow(Rails.logger).to receive(:info)

      tail.read_from(0)

      expect(Rails.logger).to have_received(:info).with("[ai_cli workflow=1 stage=2] one")
      expect(Rails.logger).to have_received(:info).with("[ai_cli workflow=1 stage=2] two")
    end
  end

  describe "#full" do
    it "returns the whole log" do
      File.write(log_path, "a\nb\n")

      expect(tail.full).to eq("a\nb\n")
    end

    it "returns an empty string when the file is missing" do
      expect(tail.full).to eq("")
    end
  end
end
