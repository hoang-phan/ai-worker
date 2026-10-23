require "rails_helper"

RSpec.describe Jira::HoursSync do
  let(:dir) { Dir.mktmpdir("hours-sync-spec") }
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

  after { FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir) }

  describe "#call" do
    it "mirrors each ticket's worklogs, linking them to the workflow, and stamps the sync time" do
      workflow = workflow_for("HRS-1")
      allow(client).to receive(:my_worklogs).with("HRS-1").and_return([ worklog("1", 3600), worklog("2", 1800) ])

      result = sync.call

      expect(result.synced).to eq(1)
      expect(TimeLog.where(ticket_key: "HRS-1").pluck(:jira_worklog_id, :seconds, :workflow_id)).to contain_exactly([ "1", 3600, workflow.id ], [ "2", 1800, workflow.id ])
      expect(workflow.reload.logged_seconds).to eq(5400)
      expect(workflow.jira_logged_synced_at).to be_within(1.minute).of(Time.current)
    end

    it "updates changed worklogs and drops the ones deleted in Jira, without duplicating" do
      workflow = workflow_for("HRS-2")
      TimeLog.create!(workflow: workflow, ticket_key: "HRS-2", jira_worklog_id: "1", started_at: Time.current, seconds: 3600)
      TimeLog.create!(workflow: workflow, ticket_key: "HRS-2", jira_worklog_id: "gone", started_at: Time.current, seconds: 900)
      allow(client).to receive(:my_worklogs).with("HRS-2").and_return([ worklog("1", 7200) ])

      sync.call

      expect(TimeLog.where(ticket_key: "HRS-2").pluck(:jira_worklog_id, :seconds)).to eq([ [ "1", 7200 ] ])
    end

    it "mirrors tickets logged this month that the app has no workflow for (so the day totals are complete)" do
      allow(client).to receive(:keys_with_my_worklogs_since).with(Date.new(2026, 9, 30)).and_return([ "OTHER-9" ])
      allow(client).to receive(:my_worklogs).with("OTHER-9").and_return([ worklog("9", 21_600) ])

      sync.call

      log = TimeLog.find_by!(ticket_key: "OTHER-9")
      expect([ log.workflow_id, log.seconds ]).to eq([ nil, 21_600 ])
    end

    it "the planner then skips a day filled directly in Jira" do
      allow(client).to receive(:keys_with_my_worklogs_since).and_return([ "OTHER-9" ])
      allow(client).to receive(:my_worklogs).with("OTHER-9").and_return([ worklog("9", 6 * 3600, started: Time.zone.local(2026, 10, 1, 9)) ])

      sync.call

      expect(Jira::TimeSlotPlanner.new(today: Date.new(2026, 10, 22)).next_start(5400).to_date).to eq(Date.new(2026, 10, 2))
    end

    it "keeps the previous rows of a failing ticket and carries on with the rest" do
      bad = workflow_for("HRS-3")
      TimeLog.create!(workflow: bad, ticket_key: "HRS-3", jira_worklog_id: "1", started_at: Time.current, seconds: 100)
      good = workflow_for("HRS-4")
      allow(client).to receive(:my_worklogs).with("HRS-3").and_raise(Jira::WorklogError, "Jira HRS-3 could not be read (HTTP 404)")
      allow(client).to receive(:my_worklogs).with("HRS-4").and_return([ worklog("4", 3600) ])

      result = sync.call

      expect(result.failed).to eq([ "HRS-3: Jira HRS-3 could not be read (HTTP 404)" ])
      expect(bad.reload.logged_seconds).to eq(100)
      expect(bad.jira_logged_synced_at).to be_nil
      expect(good.reload.logged_seconds).to eq(3600)
    end

    it "aborts when credentials are missing" do
      workflow_for("HRS-5")
      allow(client).to receive(:my_worklogs).and_raise(Jira::WorklogError.new("JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set", reason: :missing_credentials))

      expect { sync.call }.to raise_error(Jira::WorklogError, /not set/)
    end

    it "treats an ordinary Jira error whose text contains 'are not set' as a per-ticket failure" do
      bad = workflow_for("HRS-8")
      good = workflow_for("HRS-9")
      allow(client).to receive(:my_worklogs).with("HRS-8").and_raise(Jira::WorklogError, "Custom fields are not set")
      allow(client).to receive(:my_worklogs).with("HRS-9").and_return([ worklog("9", 3600) ])

      result = sync.call

      expect(result.failed).to eq([ "HRS-8: Custom fields are not set" ])
      expect(result.synced).to eq(1)
      expect(bad.reload.jira_logged_synced_at).to be_nil
      expect(good.reload.logged_seconds).to eq(3600)
    end

    it "skips projects without a Jira site URL" do
      project.update!(jira_base_url: nil)
      workflow_for("HRS-6")

      expect(sync.call.synced).to eq(0)
    end
  end

  describe "#recent" do
    it "mirrors only this month's tickets" do
      workflow_for("HRS-7")
      allow(client).to receive(:keys_with_my_worklogs_since).and_return([ "OTHER-1" ])
      allow(client).to receive(:my_worklogs).with("OTHER-1").and_return([ worklog("1", 3600) ])

      expect(sync.recent(base_url).synced).to eq(1)
      expect(client).not_to have_received(:my_worklogs).with("HRS-7")
    end
  end
end
