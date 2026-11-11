module Workflows
  # Adding and reordering the stages of a development workflow's pipeline (Workflows::StageFlow orders them by
  # `position`). Only stages the workflow hasn't reached yet can be added or moved: a pending workflow is fully
  # editable, a running one only after its current stage.
  class StageOrder
    # Stage types the "Add stage" menu offers. task / pr_review belong to their own workflow kinds, local_test has its
    # own readiness rules (Workflows::TestStageAdder). Each is added at most once.
    ADDABLE_TYPES = %w[implementation simple_implementation pr_create ci_check ci_verify pr_check].freeze
    CI_LOOP_TYPES = %w[simple_implementation pr_create ci_check ci_verify].freeze
    EXCLUSIVE_PAIRS = [ %w[implementation simple_implementation] ].freeze
    # Statuses a stage can be added or moved in: pending, plus those that label a pipeline stage.
    EDITABLE_STATUSES = ([ "pending" ] + StageFlow::STATUS_BY_STAGE_TYPE.values.map(&:to_s)).uniq.freeze

    def initialize(workflow)
      @workflow = workflow
    end

    # Pipeline stages in running order, then the rest (post-merge stages) by position, for the stage table.
    def display_stages
      ordered = ordered_stages
      ordered + (workflow.stages.to_a - ordered)
    end

    def addable_types
      return [] unless floor

      present = ordered_stages.map(&:stage_type)
      ADDABLE_TYPES.reject do |stage_type|
        present.include?(stage_type) ||
          EXCLUSIVE_PAIRS.any? { |pair| pair.include?(stage_type) && (pair & present).any? } ||
          (CI_LOOP_TYPES.include?(stage_type) && !workflow.project.ci_loop_ready?)
      end
    end

    # Creates the stage at its default place among the stages still ahead (or last). False when it can't be added.
    def add!(stage_type)
      return false unless addable_types.include?(stage_type.to_s)

      insert!(stage_type.to_s)
      true
    end

    # Callers check addability; also used for the test stages.
    def insert!(stage_type)
      Stage.transaction do
        stage = workflow.stages.create!(stage_type: stage_type, position: workflow.next_stage_position)
        ordered = ordered_stages - [ stage ]
        start = floor || 0
        rank = StageFlow::PIPELINE_ORDER.index(stage_type)
        offset = ordered.drop(start).index { |other| StageFlow::PIPELINE_ORDER.index(other.stage_type) > rank }
        ordered.insert(offset ? start + offset : ordered.size, stage)
        renumber!(ordered)
      end
    end

    def movable?(stage, direction)
      ordered = ordered_stages
      index = ordered.index(stage)
      return false unless index && floor

      target = direction.to_s == "up" ? index - 1 : index + 1
      index >= floor && target >= floor && target < ordered.size
    end

    def move!(stage, direction)
      return false unless movable?(stage, direction)

      ordered = ordered_stages
      index = ordered.index(stage)
      target = direction.to_s == "up" ? index - 1 : index + 1
      ordered[index], ordered[target] = ordered[target], ordered[index]
      Stage.transaction { renumber!(ordered) }
      true
    end

    private

    attr_reader :workflow

    def ordered_stages = workflow.stage_flow.ordered_stages

    # Index in ordered_stages of the first stage that may still change; nil when nothing can.
    def floor
      return nil unless workflow.development? && !workflow.project.personal? && EDITABLE_STATUSES.include?(workflow.status)
      return 0 if workflow.pending?

      index = ordered_stages.index(workflow.current_stage)
      index && index + 1
    end

    def renumber!(ordered)
      ordered.each.with_index(1) { |stage, position| stage.update_columns(position: position) }
      workflow.stages.reset
    end
  end
end
