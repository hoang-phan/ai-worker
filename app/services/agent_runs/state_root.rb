module AgentRuns
  # On-disk state for detached agent runs and related artifacts. Development and
  # production use Rails.root/tmp; the test env overrides config.x.state_root to
  # tmp/test_state so specs never share pid/result dirs with development data.
  module StateRoot
    def self.join(*parts)
      Pathname(Rails.configuration.x.state_root).join(*parts)
    end
  end
end
