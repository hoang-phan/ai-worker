module Projects
  # Parses and merges Project#agent_lessons: one distilled review lesson per line.
  # Merging appends new lessons unless an existing line matches case-insensitively,
  # and keeps only the newest MAX lines.
  class AgentLessons
    MAX = 40

    def initialize(text)
      @text = text.to_s
    end

    def lines
      @text.lines.map(&:strip).reject(&:blank?)
    end

    def merge(new_lessons)
      merged = lines
      Array(new_lessons).each do |lesson|
        merged << lesson unless merged.any? { |line| line.casecmp?(lesson) }
      end
      merged.last(MAX).join("\n")
    end
  end
end
