require "rails_helper"
require "tmpdir"

RSpec.describe Projects::SkillCatalog do
  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  let(:skills_dir) { File.join(@root, ".agents", "skills") }

  describe "#names" do
    it "lists skill directories sorted, ignoring files and dot-dirs" do
      %w[zeta alpha .hidden].each { |n| FileUtils.mkdir_p(File.join(skills_dir, n)) }
      File.write(File.join(skills_dir, "README.md"), "x")

      expect(described_class.new(@root).names).to eq(%w[alpha zeta])
    end

    it "is empty when the skills directory is missing" do
      expect(described_class.new(@root).names).to eq([])
    end

    it "is empty for a blank local directory" do
      expect(described_class.new("").names).to eq([])
      expect(described_class.new(nil).names).to eq([])
    end
  end

  describe "#dir" do
    it "is the expanded .agents/skills path" do
      expect(described_class.new(@root).dir).to eq(skills_dir)
    end
  end
end
