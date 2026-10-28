require "spec_helper"
require_relative "support/match_count_ratchet"

# Caps stubs of app-namespace constructors (`allow(X).to receive(:new)` /
# `expect(X).to receive(:new)`). Prefer injecting collaborators by keyword
# (see ai-worker-testing / ai-worker-refactoring). Lower or delete ALLOWLIST
# entries when you remove stubs; do not raise the caps. Listed files may have
# fewer or zero matches without failing — other tasks are clearing stubs.
module ConstructorStubRatchet
  PATTERN = /(allow|expect)\((?:(?:AiCli|Git|Github|Stages|Jira|Slack|Bugsnag|Brainstorm|Scheduling|Prompts|Ci|AgentRuns|Workflows|Projects)::[A-Za-z:]+|StageExecutor)\)\.(to|not_to) receive\(:new\)/

  # path => maximum match count. Lower or delete an entry when stubs go away.
  ALLOWLIST = {}.freeze
end

RSpec.describe "constructor stub ratchet" do
  it "does not add constructor stubs beyond ALLOWLIST maxima" do
    violations = MatchCountRatchet.violations(
      globs: [ "spec/**/*_spec.rb", "spec/support/**/*.rb" ],
      pattern: ConstructorStubRatchet::PATTERN,
      count_mode: MatchCountRatchet::PER_LINE,
      allowlist: ConstructorStubRatchet::ALLOWLIST,
      unallowlisted_hint: "not in ALLOWLIST — inject collaborators instead",
      allowlist_exceeded_hint: "lower the cap only after removing stubs"
    )

    expect(violations).to be_empty,
      "Constructor stub ratchet exceeded (inject collaborators; update ALLOWLIST only when lowering):\n#{violations.map { |v| "  #{v}" }.join("\n")}"
  end
end
