# frozen_string_literal: true

# Shared filesystem-only counting for structural ratchets. It intentionally has
# no RSpec or Rails dependency so guards can keep their scans simple.
module MatchCountRatchet
  PER_LINE = :per_line
  TOTAL_SCAN = :total_scan

  def self.violations(globs:, pattern:, count_mode:, allowlist:, unallowlisted_hint:, allowlist_exceeded_hint:)
    scanned_files(globs).filter_map do |path|
      count = match_count(path, pattern, count_mode)
      maximum = allowlist[path]

      if maximum.nil?
        next if count.zero?

        "#{path}: #{count} match(es) (#{unallowlisted_hint})"
      elsif count > maximum
        "#{path}: #{count} matches (ALLOWLIST max #{maximum} — #{allowlist_exceeded_hint})"
      end
    end
  end

  def self.scanned_files(globs)
    globs.flat_map { |glob| Dir.glob(glob) }.uniq.sort
  end
  private_class_method :scanned_files

  def self.match_count(path, pattern, count_mode)
    case count_mode
    when PER_LINE
      File.readlines(path).count { |line| line.match?(pattern) }
    when TOTAL_SCAN
      File.read(path).scan(pattern).size
    else
      raise ArgumentError, "unknown match count mode: #{count_mode.inspect}"
    end
  end
  private_class_method :match_count
end
