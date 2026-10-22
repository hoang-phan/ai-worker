module Brainstorm
  # Plain-value snapshot of the implementing workflows for one start/poll attempt. The prompt's lines and total and the
  # history.md text are all derived from the same ordered brief list, so they cannot disagree.
  class LaunchContext
    attr_reader :lines

    # Newest first, one "- brief" line per workflow.
    def self.from_workflows(workflows)
      new(lines: workflows.map { |workflow| "- #{workflow.brief}" })
    end

    def initialize(lines:)
      @lines = lines.dup.freeze
    end

    def total
      lines.size
    end

    def history_text
      lines.join("\n")
    end

    def prompt_inputs
      { backlog_lines: lines, total_in_flight: total }
    end
  end
end
