require "rails_helper"

RSpec.describe Jira::TimeLogMirror do
  let(:dir) { Dir.mktmpdir("time-log-mirror-spec") }
  let(:project) do
    Project.create!(name: "Mirror spec #{SecureRandom.hex(4)}", kind: :jira, local_directory: dir, repo_full_name: "acme/widgets", jira_base_url: "https://acme.atlassian.net")
  end
  let(:started) { Time.zone.parse("2026-10-19 09:00") }
  let(:mirror) { described_class.new }

  def workflow_for(ticket)
    project.workflows.create!(jira_ticket: ticket, branch_name: ticket.downcase, github_reviewer: "someone")
  end

  def worklog(id, seconds, at: started)
    { id: id, started: at, seconds: seconds }
  end

  def create_log(key, id, seconds, workflow: nil)
    TimeLog.create!(workflow: workflow, ticket_key: key, jira_worklog_id: id, started_at: started, seconds: seconds)
  end

  after { FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir) }

  it "creates rows for new worklogs, attached to the workflow" do
    workflow = workflow_for("MIR-1")

    mirror.replace("MIR-1", [ worklog("1", 3600), worklog("2", 1800) ], workflow: workflow)

    expect(TimeLog.where(ticket_key: "MIR-1").pluck(:jira_worklog_id, :seconds, :workflow_id))
      .to contain_exactly([ "1", 3600, workflow.id ], [ "2", 1800, workflow.id ])
  end

  it "updates changed seconds and started_at in place" do
    log = create_log("MIR-2", "1", 3600)
    later = started + 1.day

    mirror.replace("MIR-2", [ worklog("1", 7200, at: later) ], workflow: nil)

    expect(TimeLog.where(ticket_key: "MIR-2").count).to eq(1)
    expect(log.reload).to have_attributes(seconds: 7200, started_at: later)
  end

  it "deletes worklogs gone from Jira only for that ticket" do
    create_log("MIR-3", "1", 3600)
    create_log("MIR-3", "gone", 900)
    other = create_log("MIR-OTHER", "gone", 900)

    mirror.replace("MIR-3", [ worklog("1", 3600) ], workflow: nil)

    expect(TimeLog.where(ticket_key: "MIR-3").pluck(:jira_worklog_id)).to eq([ "1" ])
    expect(TimeLog.exists?(other.id)).to be(true)
  end

  it "does not overwrite the workflow of an existing row" do
    original = workflow_for("MIR-4")
    log = create_log("MIR-4", "1", 3600, workflow: original)

    mirror.replace("MIR-4", [ worklog("1", 7200) ], workflow: workflow_for("MIR-4B"))

    expect(log.reload.workflow_id).to eq(original.id)
  end

  it "removes all of the ticket's rows when Jira has no worklogs, leaving other tickets alone" do
    create_log("MIR-5", "1", 3600)
    create_log("MIR-5", "2", 900)
    other = create_log("MIR-OTHER", "1", 900)

    mirror.replace("MIR-5", [], workflow: nil)

    expect(TimeLog.where(ticket_key: "MIR-5")).to be_empty
    expect(TimeLog.exists?(other.id)).to be(true)
  end
end
