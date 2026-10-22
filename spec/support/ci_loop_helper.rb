# Shared setup for the check/verify loop specs: a Jira project with a CI command and one of its workflows.
# Builds on RecordHelper.
module CiLoopHelper
  def build_ci_project(**attrs)
    build_jira_project(flow: :ci_loop, ci_command: "bin/ci", **attrs)
  end

  def build_ci_workflow(project, **attrs)
    build_jira_workflow(project, **{ branch_name: "ci-branch", status: :implementing }.merge(attrs))
  end
end
RSpec.configure { |config| config.include CiLoopHelper }
