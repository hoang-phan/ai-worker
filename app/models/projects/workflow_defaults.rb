module Projects
  # The attributes a new workflow starts with: the next free position plus the project's default skills, PR skills
  # and reviewer. Runbooks get the same prefill as development workflows (the form shows the same fields).
  class WorkflowDefaults
    # Only runbook is special; anything else (nil, blank, unknown, pr_review) is a development workflow.
    def self.kind_for(value)
      value.to_s == "runbook" ? :runbook : :development
    end

    def initialize(project)
      @project = project
    end

    def attributes(kind: :development)
      {
        position: @project.next_workflow_position,
        skills: @project.default_skills,
        pr_skills: @project.default_pr_skills,
        github_reviewer: @project.default_reviewers,
        kind: self.class.kind_for(kind)
      }
    end
  end
end
