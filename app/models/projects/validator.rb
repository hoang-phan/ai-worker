module Projects
  # Feature-conditional and format validation rules for Project. The name presence check stays on the model.
  # The validator instance is reusable and holds no per-record state: every helper receives the project explicitly.
  class Validator < ActiveModel::Validator
    HTTP_URL = %r{\Ahttps?://[^/\s]+\S*\z}

    def validate(project)
      require_presence(project, :local_directory)
      local_directory_is_not_the_running_app(project)
      validate_repo_full_name(project) if project.jira?
      format_allow_blank(project, :jira_base_url, with: %r{\Ahttps://[^/\s]+\z}, message: "must look like https://your-site.atlassian.net")
      format_allow_blank(project, :slack_review_channel, with: /\A[CG][A-Z0-9]{8,}\z/, message: "must be a Slack channel ID like C0B5XFY2F0T")
      format_allow_blank(project, :uat_url, with: HTTP_URL, message: "must be a full URL like https://uat.example.com")
      numericality(project, :uat_test_delay_minutes, only_integer: true, greater_than_or_equal_to: 0)
      require_presence(project, :uat_url) if project.uat_test_enabled?
      format_allow_blank(project, :local_url, with: HTTP_URL, message: "must be a full URL like http://localhost:3000")
      require_presence(project, :local_url) if project.local_test_enabled?
      require_presence(project, :ci_command, message: "is required for the ci_loop flow") if project.flow_ci_loop?
      flow_needs_jira(project) unless project.jira?
      numericality(project, :ci_max_rounds, only_integer: true, greater_than: 0, less_than_or_equal_to: 20)
      require_presence(project, :brainstorm_goal) if project.brainstorm_enabled?
      numericality(project, :brainstorm_max_workflows, only_integer: true, greater_than: 0, less_than_or_equal_to: 20)
    end

    private

    def require_presence(project, attribute, **options)
      ActiveModel::Validations::PresenceValidator.new(attributes: [ attribute ], **options).validate(project)
    end

    def format_allow_blank(project, attribute, **options)
      ActiveModel::Validations::FormatValidator.new(attributes: [ attribute ], allow_blank: true, **options).validate(project)
    end

    def numericality(project, attribute, **options)
      ActiveModel::Validations::NumericalityValidator.new(attributes: [ attribute ], **options).validate(project)
    end

    def validate_repo_full_name(project)
      require_presence(project, :repo_full_name)
      ActiveModel::Validations::FormatValidator.new(
        attributes: [ :repo_full_name ],
        with: %r{\A[^/\s]+/[^/\s]+\z},
        message: "must be in the form org/repo"
      ).validate(project)
    end

    def flow_needs_jira(project)
      ActiveModel::Validations::InclusionValidator.new(
        attributes: [ :flow ],
        in: %w[standard],
        message: "ci_loop needs a Jira project"
      ).validate(project)
    end

    def local_directory_is_not_the_running_app(project)
      return unless project.runs_from_live_checkout?

      project.errors.add(:local_directory, "is this app's own live checkout; use a separate clone (see docs/ADDING_A_PROJECT.md)")
    end
  end
end
