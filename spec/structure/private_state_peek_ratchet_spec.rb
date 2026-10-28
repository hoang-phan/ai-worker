require "spec_helper"

# Caps specs that inspect private state or invoke private methods. Prefer public
# behaviour, including a small spec-local subclass when testing protected hooks.
# Lower or delete ALLOWLIST entries when remaining peeks go away; never raise caps.
RSpec.describe "private state peek ratchet" do
  PRIVATE_STATE_PATTERN = Regexp.union("instance_variable" + "_get", "." + "send(:", "." + "__send__(:")

  # path => maximum match count. Empty: no peeks remain; keep the constant so new peeks fail.
  PRIVATE_STATE_ALLOWLIST = {}.freeze

  def scanned_files
    Dir.glob("spec/**/*_spec.rb").sort
  end

  def match_count(path)
    File.read(path).scan(PRIVATE_STATE_PATTERN).size
  end

  it "does not add private-state peeks beyond ALLOWLIST maxima" do
    violations = scanned_files.filter_map do |path|
      count = match_count(path)
      max = PRIVATE_STATE_ALLOWLIST[path]

      if max.nil?
        next if count.zero?

        "#{path}: #{count} match(es) (not in ALLOWLIST — assert public behaviour instead)"
      elsif count > max
        "#{path}: #{count} matches (ALLOWLIST max #{max} — lower the cap only after removing peeks)"
      end
    end

    expect(violations).to be_empty,
      "Private state peek ratchet exceeded (assert public behaviour; update ALLOWLIST only when lowering):\n#{violations.map { |v| "  #{v}" }.join("\n") }"
  end
end
