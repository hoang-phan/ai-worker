require "spec_helper"
require_relative "support/match_count_ratchet"

# Caps wall-clock time-travel helpers. Prefer an injected `clock:` or `now:`
# seam so examples can assert exact boundaries without changing global time.
# Lower or delete ALLOWLIST entries when uses go away; never raise caps.
module TimeTravelRatchet
  TIME_TRAVEL_PATTERN = Regexp.union("travel" + "_to", "freeze" + "_time", "travel" + "(")

  # path => maximum match count. Lower or delete an entry when time travel goes away.
  TIME_TRAVEL_ALLOWLIST = {}.freeze
end

RSpec.describe "time travel ratchet" do
  it "does not add wall-clock time travel beyond ALLOWLIST maxima" do
    violations = MatchCountRatchet.violations(
      globs: [ "spec/**/*_spec.rb" ],
      pattern: TimeTravelRatchet::TIME_TRAVEL_PATTERN,
      count_mode: MatchCountRatchet::TOTAL_SCAN,
      allowlist: TimeTravelRatchet::TIME_TRAVEL_ALLOWLIST,
      unallowlisted_hint: "not in ALLOWLIST — inject a clock or now seam instead",
      allowlist_exceeded_hint: "lower the cap only after removing time travel"
    )

    expect(violations).to be_empty,
      "Time travel ratchet exceeded (inject a clock or now seam; update ALLOWLIST only when lowering):\n#{violations.map { |v| "  #{v}" }.join("\n") }"
  end
end
