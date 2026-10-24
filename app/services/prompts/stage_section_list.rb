module Prompts
  # Assembles the ordered StageSections for one stage of a workflow, with the per-stage inputs each needs.
  class StageSectionList
    DEFAULT_LATEST_LOG = ->(workflow_id) { AiCli::RunLogs.latest(workflow_id) }

    def initialize(workflow:, stage:, notifier: nil, latest_log: DEFAULT_LATEST_LOG)
      @workflow = workflow
      @stage = stage
      @project = workflow.project
      @notifier = notifier
      @latest_log = latest_log
    end

    def sections
      stage_type = stage.stage_type
      last_action = stage.last_action
      retrying = (stage.implementation? || stage.simple_implementation?) && last_action == "failed"

      [
        Prompts::StageSections::Retry.new(
          stage_type: stage_type,
          last_action: last_action,
          previous_log: (latest_log.call(workflow.id) if retrying)
        ),
        Prompts::StageSections::LocalFeedback.new(
          stage_type: stage_type,
          local_test_ready: stage.pr_check? && project.local_test_ready?,
          feedback: workflow.local_test_feedback
        ),
        Prompts::StageSections::FixedSummary.new(
          stage_type: stage_type,
          notify_enabled: stage.pr_check? && notifier.enabled?
        ),
        Prompts::StageSections::LessonsRequest.new(stage_type: stage_type),
        Prompts::StageSections::FollowUps.new(stage_type: stage_type),
        Prompts::StageSections::Lessons.new(stage_type: stage_type, lessons: project.agent_lessons),
        Prompts::StageSections::CheckOutput.new(stage_type: stage_type)
      ]
    end

    def to_s
      sections.join
    end

    private

    attr_reader :workflow, :stage, :project, :latest_log

    def notifier
      @notifier ||= Slack::ReviewNotifier.new(project)
    end
  end
end
