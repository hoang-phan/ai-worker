# Shared setup for the check/verify loop specs: a Jira project with a CI command and one of its workflows.
module CiLoopHelper
  def build_ci_project(**attrs)
    Project.create!({ name: "CI loop #{SecureRandom.hex(4)}", kind: :jira, repo_full_name: "acme/widgets",
                      local_directory: Dir.tmpdir, flow: :ci_loop, ci_command: "bin/ci" }.merge(attrs))
  end

  def build_ci_workflow(project, **attrs)
    project.workflows.create!({ jira_ticket: "CI-#{SecureRandom.hex(3)}", branch_name: "ci-branch", github_reviewer: "octocat",
                                status: :implementing }.merge(attrs))
  end
end
RSpec.configure { |config| config.include CiLoopHelper }
