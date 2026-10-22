module Stages
  # Which runner starts a stage's background run and which poller reports on it.
  # The CI check is a plain command (its exit status is the result); every other
  # stage type is an agent CLI run.
  class RunTooling
    Tooling = Data.define(:runner, :poller_class)

    PLAIN_COMMAND = Tooling.new(runner: Ci::CommandRunner, poller_class: Ci::CheckPoller)
    AGENT_CLI = Tooling.new(runner: AiCli::Runner, poller_class: AiCli::RunPoller)

    def self.for(stage)
      stage.ci_check? ? PLAIN_COMMAND : AGENT_CLI
    end
  end
end
