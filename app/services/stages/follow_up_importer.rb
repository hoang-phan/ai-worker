module Stages
  # Turns the follow-ups an agent proposed into pending development workflows (never started automatically), up to
  # MAX_FOLLOW_UPS, skipping any whose summary matches a non-done workflow's brief or an earlier proposal in the batch.
  # Returns the summaries of the workflows actually created.
  class FollowUpImporter
    MAX_FOLLOW_UPS = 2

    def initialize(project)
      @project = project
    end

    def call(proposals)
      known = Workflows::SummaryKey.set(project.workflows.where.not(status: :done))
      created = []
      proposals.each do |proposal|
        break if created.size >= MAX_FOLLOW_UPS
        next unless known.add?(Workflows::SummaryKey.call(proposal["summary"]))

        created << proposal["summary"] if build(proposal).save
      end
      created
    end

    private

    attr_reader :project

    def build(proposal)
      Workflows::ProposalWorkflow.new(project).build(proposal, status: :pending, merge_skills: false)
    end
  end
end
