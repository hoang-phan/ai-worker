# Shared builders for the Project / Workflow records most specs need. Attributes passed in override the defaults.
module RecordHelper
  def build_jira_project(**attrs)
    Project.create!({ name: "Project #{SecureRandom.hex(4)}", kind: :jira, repo_full_name: "acme/widgets",
                      local_directory: Dir.tmpdir }.merge(attrs))
  end

  def build_personal_project(**attrs)
    Project.create!({ name: "Personal #{SecureRandom.hex(4)}", kind: :personal, local_directory: Dir.tmpdir }.merge(attrs))
  end

  def build_jira_workflow(project, **attrs)
    project.workflows.create!({ jira_ticket: "TEST-#{SecureRandom.hex(3)}", branch_name: "branch-#{SecureRandom.hex(3)}",
                                github_reviewer: "octocat" }.merge(attrs))
  end

  def build_task_workflow(project, **attrs)
    project.workflows.create!({ task_description: "Do the task #{SecureRandom.hex(3)}" }.merge(attrs))
  end
end
RSpec.configure { |config| config.include RecordHelper }
