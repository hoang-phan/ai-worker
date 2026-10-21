module Stages
  # Starts a detached agent run and persists the state the scheduler needs to
  # find it on subsequent ticks.
  class AiRunLauncher
    def initialize(workflow:, stage:, project:, runner: AiCli::Runner, logs: AiCli::RunLogs)
      @workflow = workflow
      @stage = stage
      @project = project
      @runner = runner
      @logs = logs
    end

    def call(prompt_text, action: "started", mcp_config: nil, env: {}, disallowed_tools: [])
      log_path = logs.new_path(workflow.id)
      pid = runner.start(
        project.local_directory,
        prompt_text,
        log_path: log_path,
        mcp_config: mcp_config,
        env: env,
        disallowed_tools: disallowed_tools
      )

      workflow.update!(
        processing: true,
        ai_pid: pid,
        ai_log_path: log_path,
        ai_started_at: Time.current,
        ai_log_offset: 0
      )
      stage.log_run!(action)
    end

    private

    attr_reader :workflow, :stage, :project, :runner, :logs
  end
end
