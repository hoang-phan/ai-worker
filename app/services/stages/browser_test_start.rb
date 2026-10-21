module Stages
  # The shared start of the browser-test stages (uat_test and local_test): validate the browser run, put the clone on
  # the PR's branch when the kind needs it, then launch the agent with the browser server, its output directory and the
  # credentials wired in. Credentials only travel as environment variables of the agent process, never in the prompt or
  # the logs we write. Validation and Git errors propagate to StageExecutor's rescue before anything is launched.
  class BrowserTestStart
    CHECKOUT_KINDS = %i[local].freeze

    def initialize(workflow:, project:, kind:, prompt:, git:, launcher:, browser_run: AiCli::BrowserTestRun)
      @workflow = workflow
      @project = project
      @kind = kind.to_sym
      @prompt = prompt
      @git = git
      @launcher = launcher
      @browser_run = browser_run
    end

    def call
      run = browser_run.new(project, workflow, kind: kind).validate!
      git.checkout_remote_branch!(project, workflow.branch_name) if CHECKOUT_KINDS.include?(kind)
      launcher.call(prompt.body, mcp_config: run.mcp_config_path, env: run.env, disallowed_tools: run.disallowed_tools)
    end

    private

    attr_reader :workflow, :project, :kind, :prompt, :git, :launcher, :browser_run
  end
end
