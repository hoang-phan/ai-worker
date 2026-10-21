module Jira
  # Logs the same number of hours on each workflow in order, stopping at the first Jira::WorklogError.
  # Worklogs already created before the failure are kept and reported.
  class TimeLogBatch
    Result = Struct.new(:logged, :failure, keyword_init: true) do
      def success?
        failure.nil?
      end

      def message(hours)
        summary = logged.map { |log| "#{log.ticket_key} #{I18n.l(log.started_at, format: :short)}" }.to_sentence

        if success?
          "Logged #{hours} h on #{summary}."
        else
          "#{failure}.#{" Logged before that: #{summary}." if logged.any?}"
        end
      end
    end

    def initialize(logger: TimeLogger.new)
      @logger = logger
    end

    def call(workflows, hours)
      logged = []
      workflows.each do |workflow|
        logged << @logger.log(workflow, hours)
      rescue WorklogError => e
        return Result.new(logged: logged, failure: e.message)
      end
      Result.new(logged: logged, failure: nil)
    end
  end
end
