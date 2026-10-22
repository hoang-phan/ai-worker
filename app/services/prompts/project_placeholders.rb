module Prompts
  # The project-derived prompt tokens, token => value. Takes only a project.
  class ProjectPlaceholders
    def self.for(project)
      new(project).to_h
    end

    def initialize(project)
      @project = project
    end

    def to_h
      {
        "{TESTER}" => project.jira_tester.to_s,
        "{UAT_URL}" => project.uat_url.to_s,
        "{TEST_INSTRUCTIONS}" => project.test_instructions.to_s,
        "{UAT_INSTRUCTIONS}" => project.uat_instructions.to_s,
        "{LOCAL_URL}" => project.local_url.to_s,
        "{LOCAL_INSTRUCTIONS}" => project.local_instructions.to_s,
        "{CI_INSTRUCTIONS}" => project.ci_instructions.to_s,
        "{CI_VERIFY_INSTRUCTIONS}" => project.ci_verify_instructions.to_s,
        "{PR_INSTRUCTIONS}" => project.pr_instructions.to_s,
        "{CI_COMMAND}" => project.ci_command.to_s
      }
    end

    private

    attr_reader :project
  end
end
