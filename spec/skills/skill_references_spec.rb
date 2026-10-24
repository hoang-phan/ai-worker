require "spec_helper"
require "yaml"
require_relative "../support/skill_path_helper"

RSpec.describe "skill references" do
  include SkillPathHelper

  PATH_TOKEN = %r{(?:app|spec|config|db|docs|lib|bin|\.agents|\.github)/[A-Za-z0-9_./{}*,:<>-]+}.freeze

  def skill_files
    Dir.glob(".agents/skills/*/**/*.md").sort
  end

  def frontmatter(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    return {} unless match

    YAML.safe_load(match[1], permitted_classes: [], aliases: false) || {}
  end

  def path_tokens(path, metadata)
    content = File.read(path)
    backticked = content.scan(/`([^`]+)`/).flatten
    (backticked + [ metadata.fetch("description", "") ]).flat_map do |text|
      text.scan(PATH_TOKEN)
    end.map { |token| token.sub(/[.,;:]+\z/, "") }
      .reject { |token| token.include?("<") || token.include?("...") }
  end

  def path_exists?(path)
    return File.exist?(path) unless path.include?("*")

    Dir.glob(path).any?
  end

  it "has valid frontmatter and existing path references" do
    missing_paths = []

    skill_files.each do |path|
      metadata = frontmatter(path)
      skill_name = path.split("/")[2]

      expect(metadata["name"]).to eq(skill_name), "#{path}: frontmatter name must equal #{skill_name}"
      expect(metadata["description"].to_s.strip).not_to be_empty, "#{path}: frontmatter description must not be blank"

      path_tokens(path, metadata).flat_map { |token| expand_braces(token) }.uniq.each do |reference|
        missing_paths << "#{path}: #{reference}" unless path_exists?(reference)
      end
    end

    expect(missing_paths).to be_empty, "Missing skill paths:\n#{missing_paths.join("\n")}"
  end

  it "references existing ai-worker skills" do
    skill_names = Dir.glob(".agents/skills/*").filter_map do |path|
      File.basename(path) if File.directory?(path)
    end
    missing_skills = skill_files.flat_map do |path|
      File.read(path).scan(/`[^`]*(?<![.\w-])(ai-worker-[a-z0-9-]+)\b[^`]*`/).flatten.filter_map do |skill_name|
        "#{path}: #{skill_name}" unless skill_names.include?(skill_name)
      end
    end

    expect(missing_skills).to be_empty, "Missing referenced skills:\n#{missing_skills.join("\n")}"
  end
end
