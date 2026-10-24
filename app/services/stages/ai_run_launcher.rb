module Stages
  # Starts a detached agent run and persists the state the scheduler needs to
  # find it on subsequent ticks.
  class AiRunLauncher
    def initialize(workflow:, stage:, project:, runner: AiCli::Runner, logs: AiCli::RunLogs,
                   run_provider: Stages::RunProvider.new(workflow: workflow, stage: stage))
      @workflow = workflow
      @stage = stage
      @project = project
      @runner = runner
      @logs = logs
      @run_provider = run_provider
    end

    def call(prompt_text, action: "started", mcp_config: nil, env: {}, disallowed_tools: [])
      log_path = logs.new_path(workflow.id)
      provider = run_provider.override
      pid = runner.start(
        project.local_directory,
        prompt_text,
        log_path: log_path,
        mcp_config: mcp_config,
        env: env,
        disallowed_tools: disallowed_tools,
        provider: provider
      )

      workflow.update!(
        processing: true,
        ai_pid: pid,
        ai_log_path: log_path,
        ai_started_at: Time.current,
        ai_log_offset: 0,
        ai_provider: provider
      )
      stage.log_run!(action)
    end

    private

    attr_reader :workflow, :stage, :project, :runner, :logs, :run_provider
  end
end
