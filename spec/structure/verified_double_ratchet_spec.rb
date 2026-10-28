require "spec_helper"

# Caps plain doubles whose first arg is a string that looks like a constant
# (e.g. a class or module name). Prefer instance_double / class_double /
# object_double so a renamed or removed method fails the spec. Anonymous role
# doubles (e.g. named "poller") are fine. Lower or delete ALLOWLIST entries
# when matches go away; never raise.
module VerifiedDoubleRatchet
  # Plain double( whose first arg is a string literal that looks like a constant.
  PATTERN = /(?<![a-z_])double\(\s*(["'])[A-Z][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)*\1/

  # path => maximum match count. Lower or delete an entry when doubles go away.
  # ALLOWLIST = {
  #   # "spec/example_spec.rb" => 1, # reason — replace with a verifying double
  # }.freeze
  ALLOWLIST = {}.freeze
end

RSpec.describe "verified double ratchet" do
  def scanned_files
    (Dir.glob("spec/**/*_spec.rb") + Dir.glob("spec/support/**/*.rb")).uniq.sort
  end

  def match_count(path)
    File.readlines(path).count { |line| line.match?(VerifiedDoubleRatchet::PATTERN) }
  end

  it "does not add class-named unverified doubles beyond ALLOWLIST maxima" do
    violations = scanned_files.filter_map do |path|
      count = match_count(path)
      max = VerifiedDoubleRatchet::ALLOWLIST[path]

      if max.nil?
        next if count.zero?

        "#{path}: #{count} match(es) (not in ALLOWLIST — use instance_double/class_double/object_double)"
      elsif count > max
        "#{path}: #{count} matches (ALLOWLIST max #{max} — lower the cap only after converting doubles)"
      end
    end

    expect(violations).to be_empty,
      "Verified double ratchet exceeded (fake real collaborators with verifying doubles; update ALLOWLIST only when lowering, never raising):\n#{violations.map { |v| "  #{v}" }.join("\n")}"
  end
end
