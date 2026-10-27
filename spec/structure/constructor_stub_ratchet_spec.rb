require "spec_helper"

# Caps stubs of app-namespace constructors (`allow(X).to receive(:new)` /
# `expect(X).to receive(:new)`). Prefer injecting collaborators by keyword
# (see ai-worker-testing / ai-worker-refactoring). Lower or delete ALLOWLIST
# entries when you remove stubs; do not raise the caps. Listed files may have
# fewer or zero matches without failing — other tasks are clearing stubs.
RSpec.describe "constructor stub ratchet" do
  PATTERN = /(allow|expect)\((?:(?:AiCli|Git|Github|Stages|Jira|Slack|Bugsnag|Brainstorm|Scheduling|Prompts|Ci|AgentRuns|Workflows|Projects)::[A-Za-z:]+|StageExecutor)\)\.(to|not_to) receive\(:new\)/

  # path => maximum match count. Lower or delete an entry when stubs go away.
  ALLOWLIST = {
    "spec/requests/bugsnag_sync_runs_spec.rb" => 1,
    "spec/requests/jira_sync_runs_spec.rb" => 1,
    "spec/requests/project_brainstorms_spec.rb" => 1,
    "spec/requests/project_slack_syncs_spec.rb" => 1,
    "spec/services/slack/review_sync_spec.rb" => 0
  }.freeze

  def scanned_files
    (Dir.glob("spec/**/*_spec.rb") + Dir.glob("spec/support/**/*.rb")).uniq.sort
  end

  def match_count(path)
    File.readlines(path).count { |line| line.match?(PATTERN) }
  end

  it "does not add constructor stubs beyond ALLOWLIST maxima" do
    violations = scanned_files.filter_map do |path|
      count = match_count(path)
      max = ALLOWLIST[path]

      if max.nil?
        next if count.zero?

        "#{path}: #{count} match(es) (not in ALLOWLIST — inject collaborators instead)"
      elsif count > max
        "#{path}: #{count} matches (ALLOWLIST max #{max} — lower the cap only after removing stubs)"
      end
    end

    expect(violations).to be_empty,
      "Constructor stub ratchet exceeded (inject collaborators; update ALLOWLIST only when lowering):\n#{violations.map { |v| "  #{v}" }.join("\n")}"
  end
end
