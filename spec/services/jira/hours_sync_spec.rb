require "rails_helper"

RSpec.describe Jira::HoursSync do
  let_tmpdir(:dir, "hours-sync-spec")
  let(:base_url) { "https://acme.atlassian.net" }
  let!(:project) do
    build_jira_project(local_directory: dir, jira_base_url: base_url)
  end
  let(:client) { instance_double(Jira::WorklogClient, keys_with_my_worklogs_since: []) }
  let(:sync) { described_class.new(client_factory: ->(_url) { client }, today: -> { Date.new(2026, 10, 22) }) }

  def workflow_for(ticket)
    build_jira_workflow(project, jira_ticket: ticket)
  end

  def worklog(id, seconds, started: Time.zone.parse("2026-10-19 09:00"))
    { id: id, started: started, seconds: seconds }
  end

  describe "#call" do
    it "mirrors each ticket's worklogs via TimeLogMirror, linking them to the workflow, and stamps the sync time" do
      workflow = workflow_for("HRS-1")
      allow(client).to receive(:my_worklogs).with("HRS-1").and_return([ worklog("1", 3600), worklog("2", 1800) ])

      result = sync.call

      expect(result.synced).to eq(1)
      expect(TimeLog.where(ticket_key: "HRS-1").pluck(:jira_worklog_id, :seconds, :workflow_id)).to contain_exactly([ "1", 3600, workflow.id ], [ "2", 1800, workflow.id ])
      expect(workflow.reload.logged_seconds).to eq(5400)
      expect(workflow.jira_logged_synced_at).to be_within(1.minute).of(Time.current)
    end

    it "discovers tickets logged this month that the app has no workflow for (so the day totals are complete)" do
      allow(client).to receive(:keys_with_my_worklogs_since).with(Date.new(2026, 9, 30)).and_return([ "OTHER-9" ])
      allow(client).to receive(:my_worklogs).with("OTHER-9").and_return([ worklog("9", 21_600) ])

      sync.call

      log = TimeLog.find_by!(ticket_key: "OTHER-9")
      expect([ log.workflow_id, log.seconds ]).to eq([ nil, 21_600 ])
    end

    it "aggregates synced and failed counts across Jira sites" do
      other_dir = make_tmpdir("hours-sync-other")
      other = build_jira_project(local_directory: other_dir, jira_base_url: "https://other.atlassian.net", name: "Other #{SecureRandom.hex(4)}")
      workflow_for("HRS-10")
      build_jira_workflow(other, jira_ticket: "HRS-11")
      clients = {
        base_url => client,
        "https://other.atlassian.net" => instance_double(Jira::WorklogClient, keys_with_my_worklogs_since: [])
      }
      allow(clients[base_url]).to receive(:my_worklogs).with("HRS-10").and_return([ worklog("a", 3600) ])
      allow(clients["https://other.atlassian.net"]).to receive(:my_worklogs).with("HRS-11")
        .and_raise(Jira::WorklogError, "Jira HRS-11 could not be read (HTTP 404)")
      multi = described_class.new(client_factory: ->(url) { clients.fetch(url) }, today: -> { Date.new(2026, 10, 22) })

      result = multi.call

      expect(result.synced).to eq(1)
      expect(result.failed).to eq([ "HRS-11: Jira HRS-11 could not be read (HTTP 404)" ])
    end

    it "reuses one client instance per site across recent-key lookup and ticket sync" do
      workflow_for("HRS-1")
      created = []
      factory = lambda { |url|
        created << url
        client
      }
      allow(client).to receive(:my_worklogs).with("HRS-1").and_return([])
      described_class.new(client_factory: factory, today: -> { Date.new(2026, 10, 22) }).call

      expect(created).to eq([ base_url ])
      expect(client).to have_received(:keys_with_my_worklogs_since).once
      expect(client).to have_received(:my_worklogs).with("HRS-1").once
    end

    it "skips projects without a Jira site URL" do
      project.update!(jira_base_url: nil)
      workflow_for("HRS-6")

      expect(sync.call.synced).to eq(0)
    end
  end

  describe "#recent" do
    it "discovers and mirrors only this month's tickets, without stamping unrelated workflows" do
      workflow = workflow_for("HRS-7")
      allow(client).to receive(:keys_with_my_worklogs_since).and_return([ "OTHER-1" ])
      allow(client).to receive(:my_worklogs).with("OTHER-1").and_return([ worklog("1", 3600) ])

      expect(sync.recent(base_url).synced).to eq(1)
      expect(client).not_to have_received(:my_worklogs).with("HRS-7")
      expect(TimeLog.find_by!(ticket_key: "OTHER-1").workflow_id).to be_nil
      expect(workflow.reload.jira_logged_synced_at).to be_nil
    end
  end
end
