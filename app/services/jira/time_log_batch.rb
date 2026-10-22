module Jira
  # Logs the same number of hours on each workflow in order, stopping at the first Jira::WorklogError.
  # Worklogs already created before the failure are kept and reported. Before logging anything it re-reads this month's
  # worklogs from Jira, so days already filled there (by hand or by this app) are not topped up again.
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

    def initialize(logger: TimeLogger.new, hours_sync: HoursSync.new)
      @logger = logger
      @hours_sync = hours_sync
    end

    def call(workflows, hours)
      logged = []
      with_failure_result(logged) do
        refresh_recent(workflows)
        log_each(workflows, hours, logged)
      end
    end

    private

    # Runs the block and returns a successful Result, or a failed one carrying the worklogs logged so far.
    def with_failure_result(logged)
      yield
      Result.new(logged: logged, failure: nil)
    rescue WorklogError => e
      Result.new(logged: logged, failure: e.message)
    end

    def site_urls(workflows)
      workflows.map { |workflow| workflow.project.jira_base_url.presence }.compact.uniq
    end

    def refresh_recent(workflows)
      site_urls(workflows).each { |base_url| @hours_sync.recent(base_url) }
    end

    # Appends to +logged+ as it goes so a mid-batch failure still reports earlier worklogs.
    def log_each(workflows, hours, logged)
      workflows.each { |workflow| logged << @logger.log(workflow, hours) }
    end
  end
end
