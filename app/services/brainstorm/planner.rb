require "fileutils"
require "json"

module Brainstorm
  class FetchError < StandardError; end

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
    DEFAULT_MODEL = "claude-opus-5-5".freeze
    DEFAULT_EFFORT = "high".freeze
    PROMPT_HISTORY_LINES = 30
    TASK_LENGTH = 4000
    # Read-only: the agent may look at the code and git history, and write the result file, nothing else.
    ALLOWED_TOOLS = [ "Read", "Grep", "Glob", "Write", "Bash(git log:*)", "Bash(git ls-files:*)", "Bash(git status:*)", "Bash(git diff:*)" ].freeze

    Result = Struct.new(:created, :skipped, keyword_init: true)

    def self.model
      ENV["BRAINSTORM_MODEL"].presence || DEFAULT_MODEL
    end

    def self.effort
      ENV["BRAINSTORM_EFFORT"].presence || DEFAULT_EFFORT
    end

    def initialize(project)
      @project = project
      @dir = ROOT.join(project.id.to_s)
    end

    def blockers
      list = []
      list << "project kind is not personal" unless project.personal?
      list << "no goal set" if project.brainstorm_goal.blank?
      list << "local directory does not exist" unless Dir.exist?(project.local_directory.to_s)
      list
    end

    # Pending workflows; brainstorming waits until this is zero.
    def queued_count
      project.workflows.queued.count
    end

    def running?
      pid_file.exist? && AiCli::Runner.poll(pid_file.read.to_i) == :running
    end

    def last_started_at
      started_file.exist? ? Time.zone.at(started_file.read.to_f) : nil
    end

    def start
      return false if running?

      FileUtils.mkdir_p(dir)
      FileUtils.rm_f(result_file)
      history_file.write(history_lines.join("\n"))
      pid = AiCli::Runner.start(project.local_directory, prompt, log_path: log_file.to_s, allowed_tools: ALLOWED_TOOLS,
                                model: self.class.model, effort: self.class.effort)
      pid_file.write(pid)
      started_file.write(Time.current.to_f)
      true
    end

    # nil while running (or nothing started); once finished, the array of { "summary", "task" } the agent proposed.
    # Raises FetchError on failure.
    def poll
      return unless pid_file.exist?

      if AiCli::Runner.poll(pid_file.read.to_i) == :running
        return unless stale?

        clear
        raise FetchError, "agent did not finish within #{STALE_AFTER.inspect}"
      end

      clear
      read_result
    end

    # Creates a workflow per proposal (up to the project's maximum), skipping any whose summary matches an existing
    # workflow. Only while the queue is still empty, so a manual workflow added meanwhile isn't buried.
    def import(proposals)
      result = Result.new(created: [], skipped: [])
      return result if queued_count.positive?

      known = in_flight.map { |workflow| normalize(workflow.brief) }.to_set
      proposals.each do |proposal|
        break if result.created.size >= project.brainstorm_max_workflows

        key = normalize(proposal["summary"])
        if known.include?(key)
          result.skipped << proposal["summary"]
          next
        end

        workflow = project.workflows.new(
          summary: proposal["summary"], task_description: proposal["task"], skills: project.default_skills,
          status: project.brainstorm_auto_start? ? :implementing : :pending,
          position: (project.workflows.maximum(:position) || 0) + 1
        )
        if workflow.save
          known << key
          result.created << workflow.summary
        else
          result.skipped << "#{proposal['summary']} (#{workflow.errors.full_messages.to_sentence})"
        end
      end
      result
    end

    private

    attr_reader :project, :dir

    def stale?
      last_started_at.nil? || last_started_at < STALE_AFTER.ago
    end

    def clear
      FileUtils.rm_f(pid_file)
    end

    def normalize(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    # Workflows that are not in the code yet (the only ones the agent can't see by reading it).
    def in_flight
      project.workflows.development.where(status: :implementing).order(id: :desc)
    end

    def history_lines
      in_flight.map { |workflow| "- #{workflow.brief}" }
    end

    def read_result
      raise FetchError, "agent wrote no #{result_file.basename}; see #{log_file}" unless result_file.exist?

      data = JSON.parse(result_file.read)
      raise FetchError, "#{result_file.basename} is not a JSON array" unless data.is_a?(Array)

      data.filter_map do |row|
        next unless row.is_a?(Hash)

        summary = row["summary"].to_s.squish.truncate(Workflow::SUMMARY_LENGTH)
        task = row["task"].to_s.strip.truncate(TASK_LENGTH)
        { "summary" => summary, "task" => task } if summary.present? && task.present?
      end
    rescue JSON::ParserError => e
      raise FetchError, "invalid JSON in #{result_file.basename}: #{e.message}"
    end

    def prompt
      recent = history_lines.first(PROMPT_HISTORY_LINES)
      total = in_flight.count
      backlog = recent.any? ? recent.join("\n") : "(none yet)"
      more = total > recent.size ? "\n(#{total - recent.size} older ones are in #{history_file}; grep it before proposing anything that sounds familiar.)" : ""
      <<~PROMPT
        You are brainstorming the next pieces of work for a software project. The current directory is its code; read its CLAUDE.md / .agents skills and rules if present. This is a read-only run: NEVER change code, create branches, commits or PRs. The only file you may write is #{result_file}.

        GOAL (set by the project owner; it may be broad):
        #{project.brainstorm_goal}

        Workflows currently being implemented (not in the code yet), newest first, one line each. Do not propose these again, nor near-duplicates:
        #{backlog}#{more}

        Look at the code as it is now (and `git log --oneline -30`) and propose up to #{project.brainstorm_max_workflows} new, independent tasks that move the project toward the goal. Prefer the highest-value, smallest-sufficient ones; each must be doable by one unattended agent run that implements and commits it. Don't propose anything that needs secrets, production access, destructive data operations or a human decision.

        Write #{result_file} as a JSON array and nothing else:
        [{"summary":"<=#{Workflow::SUMMARY_LENGTH} chars, imperative, specific, e.g. Add empty-state to the projects table","task":"Self-contained instructions for the implementing agent: what to change, where (paths), how to verify, and what is out of scope."}]
        Write [] if nothing worthwhile is left toward the goal. Reply with one short line, e.g. "Brainstormed 3 workflows".
      PROMPT
    end

    def pid_file
      dir.join("pid")
    end

    def started_file
      dir.join("started_at")
    end

    def result_file
      dir.join("result.json")
    end

    def history_file
      dir.join("history.md")
    end

    def log_file
      dir.join("agent.log")
    end
  end
end
