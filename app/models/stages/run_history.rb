module Stages
  # Derived queries over a stage's StageRun audit log. Pure: built from the actions newest-first and never touches
  # the database, so build a fresh one per read (see Stage#run_history).
  class RunHistory
    # `actions` are the StageRun#action strings, newest first.
    def initialize(actions)
      @actions = actions.to_a
    end

    # Action of the newest run, nil when the stage has none.
    def last_action
      @actions.first
    end

    # Trailing run of failed/started rows (newest first) with no success or `resumed` in between; counts the failed ones.
    def consecutive_failures
      @actions.take_while { |action| %w[failed started].include?(action) }.count("failed")
    end

    def resolving_conflicts?
      last_action == "conflict_resolution_started"
    end

    def completed_local_test_rounds
      @actions.count("local_test_completed")
    end

    # `ci_check_completed` rounds since the last `resumed` (a person resuming an exhausted loop grants a fresh budget).
    def completed_ci_rounds
      @actions.take_while { |action| action != "resumed" }.count("ci_check_completed")
    end

    # A local test run that started but whose newest run isn't a completion (earlier completed rounds don't count).
    def local_test_unfinished?
      last = last_action
      last.present? && last != "local_test_completed"
    end
  end
end
