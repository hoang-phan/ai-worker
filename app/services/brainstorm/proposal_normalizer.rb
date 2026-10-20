module Brainstorm
  # Pure: turns the parsed rows of the agent's result.json into proposals.
  #
  # Input: the Array DetachedRun yields (any elements). Output: an Array of { "summary", "task" } string hashes.
  # Non-Hash rows and rows with a blank summary or task are dropped; the summary is squished and truncated to
  # Workflow::SUMMARY_LENGTH, the task stripped and truncated to TASK_LENGTH.
  class ProposalNormalizer
    TASK_LENGTH = 4000

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
        { "summary" => summary, "task" => task } if summary.present? && task.present?
      end
    end

    private

    attr_reader :rows
  end
end
