module Workflows
  # Builds the unsaved development workflow for an agent proposal ({"summary","task","skills"}) on a project's queue.
  class ProposalWorkflow
    def initialize(project)
      @project = project
    end

    # `merge_skills` adds the proposal's own skills after the project's defaults; otherwise only the defaults apply.
    def build(proposal, status:, merge_skills:)
      project.workflows.new(
        kind: :development, summary: proposal["summary"], task_description: proposal["task"],
        skills: merge_skills ? merged_skills(proposal) : project.default_skills,
        status: status, position: project.next_workflow_position
      )
    end

    private

    attr_reader :project

    # Default skills first, then the proposal's own, deduped; the defaults alone when the proposal names none.
    def merged_skills(proposal)
      extra = proposal["skills"].to_s
      return project.default_skills if extra.blank?

      [ project.default_skills, extra ].flat_map { |list| list.to_s.split(",").map(&:strip) }.reject(&:blank?).uniq.join(", ")
    end
  end
end
