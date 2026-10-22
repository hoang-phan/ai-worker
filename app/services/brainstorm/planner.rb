module Brainstorm
  # Brainstorms new workflows for a personal project from its standing goal ("improve the UI", "raise test
  # coverage", "suggest useful features" ...). One detached agent run in the project's local clone, read-only,
  # with a stronger model and higher effort than workflow runs (BRAINSTORM_MODEL / BRAINSTORM_EFFORT env). It
  # writes result.json; `poll` reads it once the process has finished and `import` turns it into workflows.
  #
  # It only runs while the project has no pending workflow (`Workflow.queued`): proposals wait for you to Start them.
  # Implementing workflows don't block it, but they aren't in the code yet, so the agent is shown just those to avoid
  # proposing the same thing twice (done ones are already in the code it reads). To keep its context small it gets
  # one short line per workflow (`Workflow#brief`), newest first and capped; the full list is in history.md.
  #
  # State lives in tmp/brainstorms/<project id>/: pid, started_at, result.json, history.md, agent.log.
  class Planner
    ROOT = Rails.root.join("tmp", "brainstorms")
    STALE_AFTER = 45.minutes
    DEFAULT_MODEL = "gpt-6-sol".freeze
    DEFAULT_EFFORT = "high".freeze
    TASK_LENGTH = ProposalNormalizer::TASK_LENGTH
    # Read-only: the agent may look at the code and git history, and write the result file, nothing else.
    ALLOWED_TOOLS = [ "Read", "Grep", "Glob", "Write", "Bash(git log:*)", "Bash(git ls-files:*)", "Bash(git status:*)", "Bash(git diff:*)" ].freeze

    Result = ProposalImporter::Result

    delegate :running?, :last_started_at, to: :lifecycle

    def self.model
      ENV["BRAINSTORM_MODEL"].presence || DEFAULT_MODEL
    end

    def self.effort
      ENV["BRAINSTORM_EFFORT"].presence || DEFAULT_EFFORT
    end

    def initialize(project, clock: Time, root: ROOT, lifecycle: nil)
      @project = project
      @clock = clock
      @dir = Pathname(root).join(project.id.to_s)
      @lifecycle = lifecycle || RunLifecycle.new(dir: dir, stale_after: STALE_AFTER)
    end

    def blockers
      Projects::RunBlockers.new(project).messages(:personal_kind, :brainstorm_goal, :local_directory)
    end

    # Pending workflows; brainstorming waits until this is zero.
    def queued_count
      project.workflows.queued.count
    end

    # Why brainstorming must wait right now (nil when it may run): pending workflows have to be started or deleted first.
    def wait_reason
      queued = queued_count
      "#{queued} workflow(s) still pending; start or delete them first." if queued.positive?
    end

    # Stamps the project's last-run time; callers invoke it after a successful `start`.
    def record_start!
      project.update!(brainstorm_last_run_at: clock.current)
    end

    def start
      context = launch_context
      lifecycle.start(prepare: -> { write_history(context) }, **launch_inputs(context))
    end

    # nil while running (or nothing started); once finished, the array of { "summary", "task" } the agent proposed.
    # Raises FetchError on failure.
    def poll
      context = launch_context
      lifecycle.poll(prepare: -> { write_history(context) }, **launch_inputs(context)) { |rows| ProposalNormalizer.call(rows) }
    end

    # Creates a workflow per proposal; see ProposalImporter for the rules.
    def import(proposals)
      ProposalImporter.new(project, in_flight: in_flight).call(proposals)
    end

    private

    attr_reader :project, :dir, :clock, :lifecycle

    # Workflows that are not in the code yet (the only ones the agent can't see by reading it).
    def in_flight
      project.workflows.development.where(status: :implementing).order(id: :desc)
    end

    # One read of the implementing workflows per start/poll attempt; history.md and the prompt both come from it.
    def launch_context
      LaunchContext.from_workflows(in_flight.to_a)
    end

    def launch_inputs(context)
      {
        cwd: project.local_directory,
        prompt: prompt(context),
        allowed_tools: ALLOWED_TOOLS,
        model: self.class.model,
        effort: self.class.effort
      }
    end

    def write_history(context)
      history_file.write(context.history_text)
    end

    def prompt(context)
      Prompt.new(
        goal: project.brainstorm_goal, max_workflows: project.brainstorm_max_workflows,
        result_file: lifecycle.result_path, history_file: history_file, **context.prompt_inputs
      ).to_s
    end

    def history_file
      dir.join("history.md")
    end
  end
end
