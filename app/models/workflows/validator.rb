module Workflows
  # Kind- and project-specific validation rules for Workflow. The github_pr_url format check stays on the model.
  # The validator instance is reusable and holds no per-record state: every helper receives the workflow explicitly.
  class Validator < ActiveModel::Validator
    def validate(workflow)
      require_fields(workflow, :jira_ticket, :branch_name, :github_reviewer) if jira_development?(workflow)
      require_fields(workflow, :task_description) if personal_development?(workflow)
      require_fields(workflow, :github_pr_url) if workflow.pr_review?
      pr_review_needs_github_project(workflow) if workflow.pr_review?
      variable_names_are_placeholders(workflow)
      copy_source_is_a_runbook_of_this_project(workflow) if workflow.runbook?
    end

    private

    def require_fields(workflow, *attributes)
      attributes.each { |attribute| workflow.errors.add(attribute, :blank) if workflow.public_send(attribute).blank? }
    end

    def pr_review_needs_github_project(workflow)
      workflow.errors.add(:base, "PR reviews need a Jira (GitHub-backed) project") unless workflow.project&.jira?
    end

    def variable_names_are_placeholders(workflow)
      bad = workflow.variables.keys.grep_v(Prompts::Renderer::VARIABLE_NAME)
      workflow.errors.add(:variables, "names must be letters, digits or underscores (#{bad.join(', ')})") if bad.any?
    end

    def copy_source_is_a_runbook_of_this_project(workflow)
      return unless workflow.copy_stages_from_id.present? && workflow.copy_source.nil?

      workflow.errors.add(:copy_stages_from_id, "must be a runbook workflow of this project")
    end

    def jira_development?(workflow)
      workflow.development? && workflow.project&.jira?
    end

    def personal_development?(workflow)
      workflow.development? && workflow.project&.personal?
    end
  end
end
