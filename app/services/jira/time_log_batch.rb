module Jira
  # Logs the same number of hours on each workflow in order, stopping at the first Jira::WorklogError.
  # Worklogs already created before the failure are kept and reported.
  class TimeLogBatch
    Result = Struct.new(:logged, :failure, keyword_init: true)

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
