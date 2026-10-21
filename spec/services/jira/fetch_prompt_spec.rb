require "rails_helper"

RSpec.describe Jira::FetchPrompt do
  def build(**overrides)
    described_class.new(
      jira_base_url: "https://acme.atlassian.net", assignee: "jane@acme.test", jira_project: nil, parent_ticket: nil,
      tickets_file: "/tmp/jira/tickets.json", **overrides
    ).to_s
  end

  it "interpolates the site, assignee and result file" do
    text = build
    expect(text).to include("Jira site: https://acme.atlassian.net (find its Cloud ID")
    expect(text).to include("- Assignee: jane@acme.test")
    expect(text).to include("Write the result to /tmp/jira/tickets.json as a JSON array")
  end

  it "omits the project and parent lines, leaving blank lines, when absent" do
    text = build(jira_project: "", parent_ticket: "")
    expect(text).not_to include("In this Jira project")
    expect(text).not_to include("Child of this parent")
    expect(text).to include("- Status category: \"To Do\"\n\n\n\nBuild the JQL")
  end

  it "includes the project line when jira_project is given" do
    text = build(jira_project: "UNS")
    expect(text).to include("- In this Jira project: UNS\n  (This may be a project key")
    expect(text).not_to include("Child of this parent")
  end

  it "includes the parent line when parent_ticket is given" do
    text = build(parent_ticket: "UNS-10")
    expect(text).to include("- Child of this parent ticket / epic: UNS-10\n  (This may be an issue key")
    expect(text).not_to include("In this Jira project")
  end

  it "includes both lines when both are given" do
    text = build(jira_project: "UNS", parent_ticket: "UNS-10")
    expect(text).to include("In this Jira project: UNS")
    expect(text).to include("Child of this parent ticket / epic: UNS-10")
  end
end
