module Workflows
  # The comparison key for deduping a proposed summary against workflow briefs: case, punctuation and spacing ignored.
  module SummaryKey
    def self.call(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def self.set(workflows)
      workflows.map { |workflow| call(workflow.brief) }.to_set
    end
  end
end
