require "spec_helper"

# Caps wall-clock time-travel helpers. Prefer an injected `clock:` or `now:`
# seam so examples can assert exact boundaries without changing global time.
# Lower or delete ALLOWLIST entries when uses go away; never raise caps.
RSpec.describe "time travel ratchet" do
  TIME_TRAVEL_PATTERN = Regexp.union("travel" + "_to", "freeze" + "_time", "travel" + "(")

  # path => maximum match count. Lower or delete an entry when time travel goes away.
  TIME_TRAVEL_ALLOWLIST = {}.freeze

  def scanned_files
    Dir.glob("spec/**/*_spec.rb").sort
  end

  def match_count(path)
    File.read(path).scan(TIME_TRAVEL_PATTERN).size
  end

  it "does not add wall-clock time travel beyond ALLOWLIST maxima" do
    violations = scanned_files.filter_map do |path|
      count = match_count(path)
      max = TIME_TRAVEL_ALLOWLIST[path]

      if max.nil?
        next if count.zero?

        "#{path}: #{count} match(es) (not in ALLOWLIST — inject a clock or now seam instead)"
      elsif count > max
        "#{path}: #{count} matches (ALLOWLIST max #{max} — lower the cap only after removing time travel)"
      end
    end

    expect(violations).to be_empty,
      "Time travel ratchet exceeded (inject a clock or now seam; update ALLOWLIST only when lowering):\n#{violations.map { |v| "  #{v}" }.join("\n") }"
  end
end
