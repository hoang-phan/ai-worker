require "rails_helper"

RSpec.describe Bugsnag::TriagePrompt do
  def build(**overrides)
    described_class.new(
      repo_full_name: "acme/app", bugsnag_project: "Acme Web", since: nil, min_events: 5, max_tickets: 3,
      jira_base_url: "https://acme.atlassian.net", jira_project: "UNS", known_ids: {},
      result_file: Pathname("/tmp/x/result.json"), **overrides
    ).to_s
  end

  it "falls back to 7 days ago without a last sync" do
    expect(build(since: nil)).to include("since 7 days ago with")
  end

  it "uses the ISO timestamp when given" do
    text = build(since: "2026-10-01T00:00:00Z")
    expect(text).to include("since 2026-10-01T00:00:00Z with")
    expect(text).not_to include("7 days ago")
  end

  it "lists known ids with their Jira keys" do
    text = build(known_ids: { "abc123def456" => "UNS-1", "fff000aaa111" => "UNS-2" })
    expect(text).to include("already ticketed: abc123def456 (UNS-1), fff000aaa111 (UNS-2).")
  end

  it "says none when nothing is known" do
    expect(build(known_ids: {})).to include("already ticketed: none.")
  end

  it "interpolates the result file, min events and max tickets" do
    text = build(min_events: 12, max_tickets: 4)
    expect(text).to include("with at least 12 events")
    expect(text).to include("Take the top 4 errors")
    expect(text).to include("write [] to /tmp/x/result.json")
  end
end
