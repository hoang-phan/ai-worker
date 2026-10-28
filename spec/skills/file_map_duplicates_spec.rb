require "spec_helper"
require_relative "../support/skill_path_helper"

module FileMapDuplicates
  # File-map ownership bullets: `- \`path\` — description`
  FILE_MAP_BULLET = /\A\s*-\s+`([^`]+)`\s+—/.freeze
end

RSpec.describe "skill file map duplicates" do
  include SkillPathHelper

  def skill_files
    Dir.glob(".agents/skills/*/SKILL.md").sort
  end

  def file_map_paths(skill_path)
    File.readlines(skill_path).filter_map do |line|
      match = line.match(FileMapDuplicates::FILE_MAP_BULLET)
      next unless match

      expand_braces(match[1])
    end.flatten
  end

  it "lists each path at most once within a single SKILL.md file map" do
    duplicates = skill_files.flat_map do |skill_path|
      file_map_paths(skill_path).tally.filter_map do |path, count|
        next if count == 1

        "#{skill_path}: #{path} (#{count} times)"
      end
    end

    expect(duplicates).to be_empty,
      "Duplicate file-map bullets within a skill (cross-skill pointers are OK):\n#{duplicates.join("\n")}"
  end
end
