require "spec_helper"

# Keeps production code, specs, and templates small enough to remain easy to
# navigate. Split files instead of raising these limits or ALLOWLIST caps.
RSpec.describe "file length ratchet" do
  FILE_LENGTH_APP_RUBY_LIMIT = 120
  FILE_LENGTH_SPEC_LIMIT = 200
  FILE_LENGTH_VIEW_LIMIT = 60

  # path => current maximum line count. Lower or delete entries after splitting;
  # never raise caps.
  FILE_LENGTH_ALLOWLIST = {
    # Workflow still owns the status machine; split its remaining responsibilities first.
    "app/models/workflow.rb" => 175,
    # Project validation scenarios have not yet been separated by concern.
    "spec/models/projects/validator_spec.rb" => 253,
    # Sync-cycle cases still cover polling, import, and start behaviour together.
    "spec/services/agent_runs/sync_cycle_spec.rb" => 253
  }.freeze

  def scanned_files
    Dir.glob("app/**/*.rb").sort +
      Dir.glob("spec/**/*_spec.rb").sort +
      Dir.glob("app/views/**/*.erb").sort
  end

  def default_limit_for(path)
    return FILE_LENGTH_APP_RUBY_LIMIT if path.end_with?(".rb") && path.start_with?("app/")
    return FILE_LENGTH_SPEC_LIMIT if path.start_with?("spec/")

    FILE_LENGTH_VIEW_LIMIT
  end

  def line_count(path)
    File.foreach(path).count
  end

  it "does not let files exceed their limits or ALLOWLIST caps" do
    violations = scanned_files.filter_map do |path|
      count = line_count(path)
      limit = FILE_LENGTH_ALLOWLIST.fetch(path, default_limit_for(path))

      next unless count > limit

      "#{path}: #{count} lines (maximum #{limit})"
    end

    expect(violations).to be_empty,
      "File length ratchet exceeded — split the file and never raise caps:\n#{violations.map { |v| "  #{v}" }.join("\n") }"
  end

  it "keeps ALLOWLIST accurate" do
    gone = FILE_LENGTH_ALLOWLIST.keys.reject { |path| File.exist?(path) }
    within_default_limit = FILE_LENGTH_ALLOWLIST.keys.select do |path|
      File.exist?(path) && line_count(path) <= default_limit_for(path)
    end

    expect(gone).to be_empty,
      "ALLOWLIST entries no longer exist (remove them):\n#{gone.map { |path| "  #{path}" }.join("\n") }"
    expect(within_default_limit).to be_empty,
      "ALLOWLIST entries are within the default limit (remove them; split files and never raise caps):\n#{within_default_limit.map { |path| "  #{path}" }.join("\n") }"
  end
end
