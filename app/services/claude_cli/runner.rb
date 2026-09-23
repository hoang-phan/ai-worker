require "open3"

module ClaudeCli
  class CommandError < StandardError; end

  # Runs `claude -p "<prompt>"` inside a project's local directory and
  # blocks until it finishes. This intentionally ties up the calling
  # Sidekiq thread for the duration of the run — see docs/RUNBOOK.md for
  # why that's mitigated with a dedicated, low-concurrency queue rather
  # than a spawn+poll design.
  class Runner
    def self.run(project_directory, prompt)
      new(project_directory, prompt).run
    end

    def initialize(project_directory, prompt)
      @project_directory = project_directory
      @prompt = prompt
    end

    def run
      out, err, status = Open3.capture3("claude", "-p", prompt, chdir: project_directory)
      raise CommandError, "claude -p failed: #{err.presence || out}" unless status.success?

      out
    end

    private

    attr_reader :project_directory, :prompt
  end
end
