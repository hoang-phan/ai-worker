class StageExecutor
  def initialize(workflow, stage)
    @workflow = workflow
    @stage = stage
    @project = workflow.project
  end

  def call
    case stage.stage_type
    when "implementation" then run_implementation
    when "pr_check" then run_pr_check
    end
  rescue Git::CommandError, Github::CommandError, ClaudeCli::CommandError, ArgumentError => e
    stage.update!(status: :failed)
    log(action: "failed", error: e.message)
  end

  private

  attr_reader :workflow, :stage, :project

  def run_implementation
    stage.update!(status: :in_progress)

    Git::BranchService.create_branch!(project, workflow.branch_name)
    prompt = render_prompt
    output = ClaudeCli::Runner.run(project.local_directory, prompt)

    pr_url = Github::Client.new(project).pr_url_for_branch(workflow.branch_name)
    workflow.update!(github_pr_url: pr_url)

    stage.update!(status: :completed)
    log(action: "ran_implementation", output: output)
  end

  def run_pr_check
    github = Github::Client.new(project)
    decision = github.review_decision(workflow.github_pr_url)

    case decision
    when "APPROVED"
      workflow.update!(status: :closed)
      stage.update!(status: :completed)
      log(action: "approved_closed")
    when "CHANGES_REQUESTED"
      Git::BranchService.create_branch!(project, workflow.branch_name)
      prompt = render_prompt
      output = ClaudeCli::Runner.run(project.local_directory, prompt)
      github.request_review!(workflow.github_pr_url, workflow.github_reviewer)
      log(action: "requested_changes_fixed", output: output)
    else
      log(action: "no_action_pending")
    end
  end

  def render_prompt
    template = stage.effective_template
    raise ArgumentError, "no prompt template available for stage #{stage.id}" unless template

    Prompts::Renderer.render(template.body, workflow)
  end

  def log(action:, output: nil, error: nil)
    stage.stage_runs.create!(action: action, output: output, error: error)
  end
end
