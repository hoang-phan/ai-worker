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
      run.running?
    end

    def last_started_at
      run.last_started_at
    end

    def start
      return false if running?

      FileUtils.mkdir_p(dir)
      FileUtils.rm_f(retried_file)
      log_file.write("")
      launch
      true
    end

    # nil while running (or nothing started); once finished, the array of { "summary", "task" } the agent proposed.
    # Raises FetchError on failure.
    def poll
      return unless pid_file.exist?

      unless run.running? || result_file.exist?
        FileUtils.rm_f(pid_file)
        return handle_missing_result
      end

      run.poll { |rows| normalize_rows(rows) }
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
          position: project.next_workflow_position
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

    def run
      @run ||= AiCli::DetachedRun.new(dir: dir, result_name: "result.json", stale_after: STALE_AFTER, error_class: FetchError)
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

    def launch
      history_file.write(history_lines.join("\n"))
      run.start(cwd: project.local_directory, prompt: prompt, allowed_tools: ALLOWED_TOOLS,
                model: self.class.model, effort: self.class.effort)
    end

    # The agent's final `result` event in agent.log (stream-json output), or nil if there is none.
    def final_event
      return unless log_file.exist?

      log_file.each_line.reverse_each do |line|
        next unless line.start_with?('{"type":"result"')

        return JSON.parse(line)
      end
      nil
    rescue JSON::ParserError
      nil
    end

    def failure_reason(event)
      return "no result event in the log" unless event

      [ event["subtype"], event["terminal_reason"] ].compact.join("/")
    end

    # A run that died because its API stream was cut is retried once, right away, instead of waiting for the next tick.
    def retry_after?(event)
      event && event["terminal_reason"] == "aborted_streaming" && !retried_file.exist?
    end

    # The process finished without writing result.json: retry once if its API stream was cut, else fail.
    def handle_missing_result
      event = final_event
      if retry_after?(event)
        FileUtils.touch(retried_file)
        launch
        return
      end

      raise FetchError, "agent wrote no #{result_file.basename} (#{failure_reason(event)}); see #{log_file}"
    end

    def normalize_rows(data)
      data.filter_map do |row|
        next unless row.is_a?(Hash)

        summary = row["summary"].to_s.squish.truncate(Workflow::SUMMARY_LENGTH)
        task = row["task"].to_s.strip.truncate(TASK_LENGTH)
        { "summary" => summary, "task" => task } if summary.present? && task.present?
      end
    end

    def prompt
      recent = history_lines.first(PROMPT_HISTORY_LINES)
      total = in_flight.count
      backlog = recent.any? ? recent.join("\n") : "(none yet)"
      more = total > recent.size ? "\n(#{total - recent.size} older ones are in #{history_file}; grep it before proposing anything that sounds familiar.)" : ""
      <<~PROMPT
        You are brainstorming the next pieces of work for a software project. The current directory is its code; read its CLAUDE.md / .agents skills and rules if present. Use Read, Grep and Glob to look at files; Bash is limited to simple git commands (log, ls-files, status, diff) and anything else, including compound commands with cat/ls/sed, is denied. This is a read-only run: NEVER change code, create branches, commits or PRs. The only file you may write is #{result_file}.

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

    def result_file
      dir.join("result.json")
    end

    def history_file
      dir.join("history.md")
    end

    def log_file
      run.log_path
    end

    def retried_file
      dir.join("retried")
    end
  end
end
