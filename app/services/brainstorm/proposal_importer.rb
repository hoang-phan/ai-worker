module Brainstorm
  # Turns the agent's proposals into workflows for a project (up to its maximum), skipping any whose summary matches
  # an in-flight workflow or an earlier proposal in the same batch. Only while the queue is still empty, so a manual
  # workflow added meanwhile isn't buried. `in_flight` is the project's implementing workflows.
  class ProposalImporter
    Result = Struct.new(:created, :skipped, keyword_init: true) do
      def summary
        "created #{created.size}, skipped #{skipped.size}"
      end
    end

    def initialize(project, in_flight:)
      @project = project
      @in_flight = in_flight
    end

    def call(proposals)
      result = Result.new(created: [], skipped: [])
      return result if project.workflows.queued.exists?

      known = known_keys
      proposals.each do |proposal|
        break if full?(result)

        import_proposal(proposal, known, result)
      end
      result
    end

    private

    attr_reader :project, :in_flight

    def known_keys
      Workflows::SummaryKey.set(in_flight)
    end

    # Only created workflows count towards the maximum; skipped proposals don't.
    def full?(result)
      result.created.size >= project.brainstorm_max_workflows
    end

    def import_proposal(proposal, known, result)
      key = Workflows::SummaryKey.call(proposal["summary"])
      return result.skipped << proposal["summary"] if known.include?(key)

      workflow = build(proposal)
      if workflow.save
        known << key
        result.created << workflow.summary
      else
        result.skipped << "#{proposal['summary']} (#{workflow.errors.full_messages.to_sentence})"
      end
    end

    def build(proposal)
      Workflows::ProposalWorkflow.new(project).build(
        proposal, merge_skills: true
      )
    end
  end
end
