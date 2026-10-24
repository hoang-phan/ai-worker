require "spec_helper"

RSpec.describe "review skill routing" do
  REVIEW_SKILL_PATH = ".agents/skills/ai-worker-review/SKILL.md".freeze

  def review_skill_text
    File.read(REVIEW_SKILL_PATH)
  end

  def routing_rows
    review_skill_text.lines.filter_map do |line|
      cells = line.strip.split("|").map(&:strip)
      skill_name = cells.last[/\A`(ai-worker-[a-z0-9-]+)`\z/, 1] if cells.length >= 3

      [ cells[1], skill_name ] if skill_name
    end
  end

  def skill_names
    Dir.children(".agents/skills").select do |name|
      File.directory?(File.join(".agents/skills", name))
    end.sort
  end

  it "routes every subsystem skill" do
    routed_skills = routing_rows.map(&:last)
    text_outside_table = review_skill_text.lines.reject { |line| line.start_with?("   |") }.join
    missing_skills = skill_names.reject do |skill_name|
      skill_name == "ai-worker-review" || routed_skills.include?(skill_name) ||
        (skill_name == "ai-worker-refactoring" && text_outside_table.include?("`#{skill_name}`"))
    end

    expect(missing_skills).to be_empty, "Missing review routing skills:\n#{missing_skills.join("\n")}"
  end

  it "uses each skill in only one routing row" do
    duplicate_skills = routing_rows.map(&:last).tally.select { |_, count| count > 1 }.keys

    expect(duplicate_skills).to be_empty, "Duplicate review routing skills:\n#{duplicate_skills.join("\n")}"
  end

  it "keeps the spec fallback as the last routing row" do
    expect(routing_rows.last).to eq([ "any `spec/**` not already matched above", "ai-worker-testing" ])
  end
end
