require "spec_helper"
require_relative "support/match_count_ratchet"

# Caps specs that inspect private state or invoke private methods. Prefer public
# behaviour, including a small spec-local subclass when testing protected hooks.
# Lower or delete ALLOWLIST entries when remaining peeks go away; never raise caps.
module PrivateStatePeekRatchet
  PRIVATE_STATE_PATTERN = Regexp.union("instance_variable" + "_get", "." + "send(:", "." + "__send__(:")

  # path => maximum match count. Empty: no peeks remain; keep the constant so new peeks fail.
  PRIVATE_STATE_ALLOWLIST = {}.freeze
end

RSpec.describe "private state peek ratchet" do
  it "does not add private-state peeks beyond ALLOWLIST maxima" do
    violations = MatchCountRatchet.violations(
      globs: [ "spec/**/*_spec.rb" ],
      pattern: PrivateStatePeekRatchet::PRIVATE_STATE_PATTERN,
      count_mode: MatchCountRatchet::TOTAL_SCAN,
      allowlist: PrivateStatePeekRatchet::PRIVATE_STATE_ALLOWLIST,
      unallowlisted_hint: "not in ALLOWLIST — assert public behaviour instead",
      allowlist_exceeded_hint: "lower the cap only after removing peeks"
    )

    expect(violations).to be_empty,
      "Private state peek ratchet exceeded (assert public behaviour; update ALLOWLIST only when lowering):\n#{violations.map { |v| "  #{v}" }.join("\n") }"
  end
end
