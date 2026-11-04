module Workflows
  # The optional local_test / uat_test stages of a development workflow. A project makes them available by saving the
  # test credentials; a workflow only runs them when it has the stage (seeded at creation when the project opts in to
  # auto-include, otherwise added by hand here while the stage can still be reached).
  class TestStageAdder
    BEFORE_PR_HANDOFF = %w[pending implementing opening_pr ci_checking ci_verifying].freeze
    BEFORE_JIRA_UPDATE = (BEFORE_PR_HANDOFF + %w[local_testing reviewing done merged]).freeze
    # stage_type => statuses it can still be added in
    OPEN_STATUSES = { "local_test" => BEFORE_PR_HANDOFF, "uat_test" => BEFORE_JIRA_UPDATE }.freeze
    LABELS = { "local_test" => "Add local test stage", "uat_test" => "Add UAT test stage" }.freeze

    def initialize(workflow)
      @workflow = workflow
    end

    def addable_test_stages
      OPEN_STATUSES.keys.select { |stage_type| addable?(stage_type) }
    end

    def addable?(stage_type)
      stage_type = stage_type.to_s
      OPEN_STATUSES.key?(stage_type) &&
        workflow.development? &&
        ready?(stage_type) &&
        OPEN_STATUSES.fetch(stage_type).include?(workflow.status) &&
        !workflow.stages.exists?(stage_type: stage_type)
    end

    # False when the stage can't be added (not ready, already there, too late); the caller reports it.
    def add_test_stage!(stage_type)
      return false unless addable?(stage_type)

      workflow.stages.create!(stage_type: stage_type.to_s)
      true
    end

    private

    attr_reader :workflow

    def ready?(stage_type)
      stage_type == "local_test" ? workflow.project.local_test_ready? : workflow.project.uat_test_ready?
    end
  end
end
