require "spec_helper"

# Caps global class/singleton-method and constant stubs. Prefer injecting
# collaborators, and use the documented AiCli::Runner subprocess boundary only
# for :start and :poll. Lower or delete ALLOWLIST entries when stubs go away;
# never raise caps.
module GlobalStubRatchet
  NAMESPACES = "AiCli|Git|Github|Stages|Jira|Slack|Bugsnag|Brainstorm|Scheduling|Prompts|Ci|AgentRuns|Workflows|Projects"
  APP_CONSTANT = "(?:#{NAMESPACES})::[A-Za-z:]+|StageExecutor|[A-Z][A-Za-z0-9_]*Job"
  RECEIVER = "(?:Rails(?:\\.[A-Za-z_]+)*|described_class|#{APP_CONSTANT})"
  RUNNER_RECEIVE = "(?:allow|expect)\\(AiCli::Runner\\)\\.(?:to|not_to) receive\\((?!:new\\))(?!:(?:start|poll)\\))"
  OTHER_RECEIVE = "(?:allow|expect)\\((?!AiCli::Runner\\))#{RECEIVER}\\)\\.(?:to|not_to) receive\\((?!:new\\))"
  PATTERN = Regexp.union(/#{RUNNER_RECEIVE}/, /#{OTHER_RECEIVE}/, /stub_const\(/, /(?:allow|expect)_any_instance_of\(/)

  # path => maximum match count. Lower or delete an entry when stubs go away.
  ALLOWLIST = {}.freeze
end

RSpec.describe "global stub ratchet" do
  def scanned_files
    (Dir.glob("spec/**/*_spec.rb") + Dir.glob("spec/support/**/*.rb")).uniq.sort
  end

  def match_count(path)
    File.readlines(path).count { |line| line.match?(GlobalStubRatchet::PATTERN) }
  end

  it "does not add global stubs beyond ALLOWLIST maxima" do
    violations = scanned_files.filter_map do |path|
      count = match_count(path)
      max = GlobalStubRatchet::ALLOWLIST[path]

      if max.nil?
        next if count.zero?

        "#{path}: #{count} match(es) (not in ALLOWLIST — inject collaborators or assert real behaviour)"
      elsif count > max
        "#{path}: #{count} matches (ALLOWLIST max #{max} — lower the cap only after removing stubs)"
      end
    end

    expect(violations).to be_empty,
      "Global stub ratchet exceeded (inject collaborators; update ALLOWLIST only when lowering, never raising):\n#{violations.map { |v| "  #{v}" }.join("\n")}"
  end
end
