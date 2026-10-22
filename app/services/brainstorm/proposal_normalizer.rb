module Brainstorm
  # Pure: turns the parsed rows of the agent's result.json into proposals.
  #
  # Input: the Array DetachedRun yields (any elements). Output: an Array of { "summary", "task" } string hashes, plus a "skills" string
  # when the row names any (an Array or comma string; entries not matching SKILL_NAME dropped, deduped, at most
  # MAX_SKILLS, joined with ", "; the key is absent otherwise). Non-Hash rows and rows with a blank summary or task are dropped; the summary is squished and truncated to
  # Workflow::SUMMARY_LENGTH, the task stripped and truncated to TASK_LENGTH.
  class ProposalNormalizer
    TASK_LENGTH = 4000
    MAX_SKILLS = 6
    SKILL_NAME = /\A[\w:.\-\/]+\z/

    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = rows
    end

    def call
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        summary = row["summary"].to_s.squish.truncate(Workflow::SUMMARY_LENGTH)
        task = row["task"].to_s.strip.truncate(TASK_LENGTH)
        next unless summary.present? && task.present?

        skills = clean_skills(row["skills"])
        { "summary" => summary, "task" => task }.tap { |proposal| proposal["skills"] = skills if skills }
      end
    end

    private

    def clean_skills(value)
      names = value.is_a?(Array) ? value : value.to_s.split(",")
      names = names.filter_map { |name| name.to_s.strip if name.is_a?(String) || name.is_a?(Symbol) }
      names.grep(SKILL_NAME).uniq.first(MAX_SKILLS).join(", ").presence
    end

    attr_reader :rows
  end
end
