module Brainstorm
  # Turns the agent's proposals into workflows for a project (up to its maximum), skipping any whose summary matches
  # an in-flight workflow or an earlier proposal in the same batch. Only while the queue is still empty, so a manual
  # workflow added meanwhile isn't buried. `in_flight` is the project's implementing workflows.
  class ProposalImporter
    Result = Struct.new(:created, :skipped, keyword_init: true)

    def initialize(project, in_flight:)
      @project = project
      @in_flight = in_flight
    end

    def call(proposals)
      result = Result.new(created: [], skipped: [])
      return result if project.workflows.queued.exists?

      known = in_flight.map { |workflow| normalize(workflow.brief) }.to_set
      proposals.each do |proposal|
        break if result.created.size >= project.brainstorm_max_workflows

        key = normalize(proposal["summary"])
        if known.include?(key)
          result.skipped << proposal["summary"]
          next
        end

        workflow = build(proposal)
        if workflow.save
          known << key
          result.created << workflow.summary
        else
          result.skipped << "#{proposal['summary']} (#{workflow.errors.full_messages.to_sentence})"
        end
      end
      result
    end

    private

    attr_reader :project, :in_flight

    def build(proposal)
      project.workflows.new(
        summary: proposal["summary"], task_description: proposal["task"], skills: project.default_skills,
        status: project.brainstorm_auto_start? ? :implementing : :pending,
        position: project.next_workflow_position
      )
    end

    def normalize(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end
  end
end
