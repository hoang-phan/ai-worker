module Brainstorm
  # Builds the text the brainstorm agent is run with. Takes plain values so it needs neither the DB nor the filesystem.
  class Prompt
    HISTORY_LINES = 30

    def initialize(goal:, max_workflows:, backlog_lines:, total_in_flight:, result_file:, history_file:)
      @goal = goal
      @max_workflows = max_workflows
      @backlog_lines = backlog_lines
      @total_in_flight = total_in_flight
      @result_file = result_file
      @history_file = history_file
    end

    def to_s
      recent = backlog_lines.first(HISTORY_LINES)
      backlog = recent.any? ? recent.join("\n") : "(none yet)"
      more = total_in_flight > recent.size ? "\n(#{total_in_flight - recent.size} older ones are in #{history_file}; grep it before proposing anything that sounds familiar.)" : ""
      <<~PROMPT
        You are brainstorming the next pieces of work for a software project. The current directory is its code; read its CLAUDE.md / .agents skills and rules if present. Use Read, Grep and Glob to look at files; Bash is limited to simple git commands (log, ls-files, status, diff) and anything else, including compound commands with cat/ls/sed, is denied. This is a read-only run: NEVER change code, create branches, commits or PRs. The only file you may write is #{result_file}.

        GOAL (set by the project owner; it may be broad):
        #{goal}

        Workflows currently being implemented (not in the code yet), newest first, one line each. Do not propose these again, nor near-duplicates:
        #{backlog}#{more}

        Look at the code as it is now (and `git log --oneline -30`) and propose up to #{max_workflows} new, independent tasks that move the project toward the goal. Prefer the highest-value, smallest-sufficient ones; each must be doable by one unattended agent run that implements and commits it. Don't propose anything that needs secrets, production access, destructive data operations or a human decision.

        Write #{result_file} as a JSON array and nothing else:
        [{"summary":"<=#{Workflow::SUMMARY_LENGTH} chars, imperative, specific, e.g. Add empty-state to the projects table","task":"Self-contained instructions for the implementing agent: what to change, where (paths), how to verify, and what is out of scope.","skills":["optional: names of the project's own skills"]}]
        "skills" is optional: the `name` from the frontmatter of the repo's own skills (.agents/skills/*/SKILL.md or .claude/skills/*/SKILL.md) that the implementing agent should apply for that task. Only use names that exist in the repo, and omit the key when none fit.
        Write [] if nothing worthwhile is left toward the goal. Reply with one short line, e.g. "Brainstormed 3 workflows".
      PROMPT
    end

    private

    attr_reader :goal, :max_workflows, :backlog_lines, :total_in_flight, :result_file, :history_file
  end
end
