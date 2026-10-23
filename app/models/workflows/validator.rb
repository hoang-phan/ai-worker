module Workflows
  # Kind- and project-specific validation rules for Workflow. The github_pr_url format check stays on the model.
  class Validator < ActiveModel::Validator
    def validate(workflow)
      @workflow = workflow
      require_fields(:jira_ticket, :branch_name, :github_reviewer) if jira_development?
      require_fields(:task_description) if personal_development?
      require_fields(:github_pr_url) if workflow.pr_review?
      pr_review_needs_github_project if workflow.pr_review?
      variable_names_are_placeholders
      copy_source_is_a_runbook_of_this_project if workflow.runbook?
    end

    private

    attr_reader :workflow

    def require_fields(*attributes)
      attributes.each { |attribute| workflow.errors.add(attribute, :blank) if workflow.public_send(attribute).blank? }
    end

    def pr_review_needs_github_project
      workflow.errors.add(:base, "PR reviews need a Jira (GitHub-backed) project") unless workflow.project&.jira?
    end

    def variable_names_are_placeholders
      bad = workflow.variables.keys.grep_v(Prompts::Renderer::VARIABLE_NAME)
      workflow.errors.add(:variables, "names must be letters, digits or underscores (#{bad.join(', ')})") if bad.any?
    end

    def copy_source_is_a_runbook_of_this_project
      return unless workflow.copy_stages_from_id.present? && workflow.copy_source.nil?

      workflow.errors.add(:copy_stages_from_id, "must be a runbook workflow of this project")
    end

    def jira_development?
      workflow.development? && workflow.project&.jira?
    end

    def personal_development?
      workflow.development? && workflow.project&.personal?
    end
  end
end
