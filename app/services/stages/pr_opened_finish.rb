module Stages
  # What follows a PR being opened, whichever stage opened it (the implementation run, or the pr_create stage when the
  # project has one): record its URL, queue local testing when applicable, then hand an otherwise-ready PR to reviewers.
  class PrOpenedFinish
    def initialize(workflow:, stage:, project:, github:, handoff:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @handoff = handoff
    end

    # `action` is the StageRun logged for the stage that opened the PR.
    def call(output, action:)
      pr_url = github.find_pr_url(branch_name: workflow.branch_name, jira_ticket: workflow.jira_ticket, output: output)
      testing_locally = workflow.development? && project.local_test_ready?
      workflow.update!(Workflow::AI_RUN_RESET.merge(github_pr_url: pr_url, status: testing_locally ? :local_testing : :reviewing))
      stage.log_run!(action, output: output)
      # Auto-merge waits until the local test passed, so a PR can't merge while it is still being tested.
      handoff.enable_auto_merge!(pr_url) unless testing_locally
      handoff.notify_reviewers! unless testing_locally
    end

    private

    attr_reader :workflow, :stage, :project, :github, :handoff
  end
end
