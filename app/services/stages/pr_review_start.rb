module Stages
  # The start of a pr_review stage (someone else's PR, found in a Slack mention): skip a PR that is no longer open,
  # otherwise put the clone on its head branch for context, then let the agent review it, post the GitHub verdict and
  # reply in the Slack thread — the prompt tells it to do all three. Github/Git errors propagate to StageExecutor's rescue.
  class PrReviewStart
    def initialize(workflow:, stage:, project:, github:, git:, prompt:, launcher:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @prompt = prompt
      @launcher = launcher
    end

    def call
      info = github.pr_info(workflow.github_pr_url)

      unless info["state"] == "OPEN"
        workflow.update!(status: :done)
        return stage.log_run!("pr_not_open_skipped")
      end

      if info["cross_repository"]
        github.checkout_pr!(workflow.github_pr_url)
      else
        git.checkout_remote_branch!(project, info["head_ref"])
      end
      launcher.call(prompt.body)
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :prompt, :launcher
  end
end
