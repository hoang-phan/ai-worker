require "rails_helper"

RSpec.describe Workflows::SettingLists do
  let(:workflow_settings_class) { Struct.new(:skills, :pr_skills, :github_reviewer) }
  let(:settings) { workflow_settings_class.new }
  let(:lists) { described_class.new(settings) }

  describe "#reviewer_list" do
    it "splits on commas and whitespace, drops blanks and duplicates" do
      settings.github_reviewer = " alice, bob  carol,,alice ,\n"

      expect(lists.reviewer_list).to eq(%w[alice bob carol])
    end

    it "returns an empty list for blank or nil input" do
      expect(lists.reviewer_list).to eq([])

      settings.github_reviewer = "  , "
      expect(lists.reviewer_list).to eq([])
    end

    it "parses a simple pair" do
      settings.github_reviewer = "a, b"

      expect(lists.reviewer_list).to eq(%w[a b])
    end
  end

  describe "#skill_list and #pr_skill_list" do
    it "splits on commas only, strips and drops blanks, keeping duplicates and inner spaces" do
      settings.skills = " a , b c,, a ,"
      settings.pr_skills = "x,\n y ,,"

      expect(lists.skill_list).to eq([ "a", "b c", "a" ])
      expect(lists.pr_skill_list).to eq(%w[x y])
    end

    it "returns empty lists for nil" do
      expect(lists.skill_list).to eq([])
      expect(lists.pr_skill_list).to eq([])
    end
  end
end
