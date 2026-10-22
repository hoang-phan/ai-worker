require "yaml"

module Prompts
  # The specialised subagents a project defines in `<directory>/.claude/agents/*.md` (Claude Code loads them itself):
  # name and a short description each, read from the YAML frontmatter. Files without a name or with unreadable
  # frontmatter are ignored.
  class SubagentRoster
    MAX_ENTRIES = 20
    DESCRIPTION_LIMIT = 200
    FRONTMATTER = /\A---\s*\n(.*?)\n---\s*(?:\n|\z)/m

    def initialize(directory)
      @directory = directory
    end

    def entries
      return [] if directory.blank?

      Dir.glob(File.join(directory.to_s, ".claude", "agents", "*.md"))
        .filter_map { |path| entry(path) }
        .sort_by { |entry| entry[:name] }
        .first(MAX_ENTRIES)
    end

    private

    attr_reader :directory

    def entry(path)
      match = FRONTMATTER.match(File.read(path))
      return unless match

      data = YAML.safe_load(match[1])
      return unless data.is_a?(Hash)

      name = data["name"].to_s.squish
      return if name.empty?

      { name: name, description: data["description"].to_s.squish.truncate(DESCRIPTION_LIMIT) }
    rescue Psych::Exception, SystemCallError, EncodingError
      nil
    end
  end
end
