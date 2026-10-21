module Ci
  # Starts the project's CI command (a trusted project setting, e.g. `bin/ci`) detached in its clone and returns its pid
  # at once, like AiCli::Runner does for the agent: the run can take 20+ minutes and a job must never wait on it.
  # Its own process group, so a stale run can be killed with everything it started. `start` has the same signature as AiCli::Runner.start so Stages::AiRunLauncher launches either.
  class CommandRunner
    def self.start(project_directory, command, log_path:, env: {}, **)
      FileUtils.mkdir_p(File.dirname(log_path))

      Process.spawn(
        AiCli::Runner::LEAKED_ENV.index_with(nil).merge(env.transform_values(&:to_s)),
        "bash", "-lc", command,
        chdir: project_directory,
        pgroup: true,
        in: File::NULL,
        out: [ log_path, "a" ],
        err: [ log_path, "a" ]
      )
    end
  end
end
