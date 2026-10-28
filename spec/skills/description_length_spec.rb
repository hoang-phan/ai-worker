require "spec_helper"
require "yaml"

RSpec.describe "skill description lengths" do
  def skill_md_files
    Dir.glob(".agents/skills/*/SKILL.md").sort
  end

  def parse_frontmatter!(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    expect(match).not_to be_nil, "#{path}: missing YAML frontmatter"

    metadata = YAML.safe_load(match[1], permitted_classes: [], aliases: false)
    expect(metadata).to be_a(Hash), "#{path}: frontmatter must parse as a YAML mapping"
    metadata
  rescue Psych::SyntaxError => e
    raise RSpec::Expectations::ExpectationNotMetError, "#{path}: frontmatter YAML parse error: #{e.message}"
  end

  it "limits frontmatter descriptions to 300 characters" do
    offenders = skill_md_files.filter_map do |path|
      length = parse_frontmatter!(path).fetch("description", "").length
      "#{path}: #{length} characters" if length > 300
    end

    expect(offenders).to be_empty, "Descriptions over 300 characters:\n#{offenders.join("\n") }"
  end
end
