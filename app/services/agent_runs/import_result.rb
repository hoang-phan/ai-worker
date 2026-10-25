module AgentRuns
  class ImportResult < Struct.new(:blockers, :created, :skipped, :failed, :skipped_reasons, keyword_init: true)
    def self.empty(blockers = [])
      new(blockers: blockers, created: [], skipped: [], failed: [], skipped_reasons: Hash.new(0))
    end

    def summary
      skipped_text = "skipped #{skipped.size}"
      skipped_text += " (#{skipped_reasons.map { |reason, count| "#{count} #{reason}" }.join(", ")})" if skipped_reasons&.any?
      "created #{created.size}, #{skipped_text}, failed #{failed.size}"
    end

    def record_save(record, label)
      if record.save
        created << label
      else
        failed << "#{label}: #{record.errors.full_messages.to_sentence}"
      end
    end
  end
end
