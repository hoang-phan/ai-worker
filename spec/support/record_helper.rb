# Shared builders for the Project / Workflow records most specs need. Attributes passed in override the defaults.
module RecordHelper
  # All-digit suffix so keys always match Jira::TicketRef::KEY_PATTERN (hex letters would truncate or reject them).
  JIRA_TICKET_SEQUENCE = Enumerator.produce(100_000) { |n| n + 1 }
  PR_NUMBER_SEQUENCE = Enumerator.produce(1) { |n| n + 1 }

  def build_jira_project(**attrs)
    Project.create!({ name: "Project #{SecureRandom.hex(4)}", kind: :jira, repo_full_name: "acme/widgets",
                      local_directory: Dir.tmpdir }.merge(attrs))
  end

  def build_personal_project(**attrs)
    Project.create!({ name: "Personal #{SecureRandom.hex(4)}", kind: :personal, local_directory: Dir.tmpdir }.merge(attrs))
  end

  # Fills the columns in Workflow::AI_RUN_RESET for an in-progress AI run.
  def running_ai_run(**overrides)
    { processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 0 }.merge(overrides)
  end

  def build_jira_workflow(project, **attrs)
    project.workflows.create!({ jira_ticket: "TEST-#{JIRA_TICKET_SEQUENCE.next}", branch_name: "branch-#{SecureRandom.hex(3)}",
                                github_reviewer: "octocat" }.merge(attrs))
  end

  def build_task_workflow(project, **attrs)
    project.workflows.create!({ task_description: "Do the task #{SecureRandom.hex(3)}" }.merge(attrs))
  end

  def build_runbook_workflow(project, **attrs)
    project.workflows.create!({ kind: :runbook }.merge(attrs))
  end

  # The project must be a Jira (GitHub-backed) one: Workflows::Validator rejects PR reviews on personal projects.
  def build_pr_review_workflow(project, **attrs)
    project.workflows.create!({ kind: :pr_review,
                                github_pr_url: "https://github.com/acme/widgets/pull/#{PR_NUMBER_SEQUENCE.next}" }.merge(attrs))
  end

  def build_runbook_stage(workflow, **attrs)
    workflow.stages.create!({ stage_type: :runbook_step, name: "Step" }.merge(attrs))
  end
end
RSpec.configure { |config| config.include RecordHelper }
