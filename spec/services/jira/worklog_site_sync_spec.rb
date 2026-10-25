require "rails_helper"

RSpec.describe Jira::WorklogSiteSync do
  let(:client) { instance_double(Jira::WorklogClient) }
  let(:mirror) { instance_double(Jira::TimeLogMirror, replace: nil) }
  let(:now) { Time.zone.parse("2026-10-22 12:00") }
  let(:clock) { -> { now } }
  let(:sync) { described_class.new(client: client, mirror: mirror, clock: clock) }

  def workflow(key)
    instance_double(Workflow, jira_key: key, update_columns: true)
  end

  def worklogs(*ids)
    ids.map { |id| { id: id, started: now, seconds: 3600 } }
  end

  describe "#call" do
    it "mirrors each ticket through the mirror, linking the workflow, and stamps synced workflows with the clock" do
      wf = workflow("HRS-1")
      allow(client).to receive(:my_worklogs).with("HRS-1").and_return(worklogs("1", "2"))

      result = sync.call([ wf ], [ "HRS-1" ])

      expect(result).to have_attributes(synced: 1, failed: [])
      expect(mirror).to have_received(:replace).with("HRS-1", worklogs("1", "2"), workflow: wf)
      expect(wf).to have_received(:update_columns).with(jira_logged_synced_at: now)
    end

    it "deduplicates keys while preserving first-seen order" do
      seen = []
      allow(client).to receive(:my_worklogs) { |key|
        seen << key
        []
      }

      sync.call([], %w[A-1 B-2 A-1 C-3 B-2])

      expect(seen).to eq(%w[A-1 B-2 C-3])
    end

    it "uses the last workflow when the same ticket key appears more than once" do
      first = workflow("DUP-1")
      last = workflow("DUP-1")
      allow(client).to receive(:my_worklogs).with("DUP-1").and_return([])

      sync.call([ first, last ], [ "DUP-1" ])

      expect(mirror).to have_received(:replace).with("DUP-1", [], workflow: last)
      expect(first).to have_received(:update_columns).with(jira_logged_synced_at: now)
      expect(last).to have_received(:update_columns).with(jira_logged_synced_at: now)
    end

    it "records an ordinary WorklogError, skips mirroring that ticket, continues, and does not stamp the failed workflow" do
      bad = workflow("HRS-3")
      good = workflow("HRS-4")
      allow(client).to receive(:my_worklogs).with("HRS-3").and_raise(Jira::WorklogError, "Jira HRS-3 could not be read (HTTP 404)")
      allow(client).to receive(:my_worklogs).with("HRS-4").and_return(worklogs("4"))

      result = sync.call([ bad, good ], %w[HRS-3 HRS-4])

      expect(result.failed).to eq([ "HRS-3: Jira HRS-3 could not be read (HTTP 404)" ])
      expect(result.synced).to eq(1)
      expect(mirror).not_to have_received(:replace).with("HRS-3", anything, anything)
      expect(mirror).to have_received(:replace).with("HRS-4", worklogs("4"), workflow: good)
      expect(bad).not_to have_received(:update_columns)
      expect(good).to have_received(:update_columns).with(jira_logged_synced_at: now)
    end

    it "aborts when credentials are missing" do
      wf = workflow("HRS-5")
      allow(client).to receive(:my_worklogs)
        .and_raise(Jira::WorklogError.new("JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set", reason: :missing_credentials))

      expect { sync.call([ wf ], [ "HRS-5" ]) }.to raise_error(Jira::WorklogError, /not set/)
      expect(mirror).not_to have_received(:replace)
      expect(wf).not_to have_received(:update_columns)
    end

    it "treats an ordinary Jira error whose text contains 'are not set' as a per-ticket failure" do
      bad = workflow("HRS-8")
      good = workflow("HRS-9")
      allow(client).to receive(:my_worklogs).with("HRS-8").and_raise(Jira::WorklogError, "Custom fields are not set")
      allow(client).to receive(:my_worklogs).with("HRS-9").and_return(worklogs("9"))

      result = sync.call([ bad, good ], %w[HRS-8 HRS-9])

      expect(result.failed).to eq([ "HRS-8: Custom fields are not set" ])
      expect(result.synced).to eq(1)
      expect(bad).not_to have_received(:update_columns)
      expect(good).to have_received(:update_columns).with(jira_logged_synced_at: now)
    end

    it "syncs keys with no matching workflows and stamps nothing" do
      allow(client).to receive(:my_worklogs).with("OTHER-9").and_return(worklogs("9"))

      result = sync.call([], [ "OTHER-9" ])

      expect(result.synced).to eq(1)
      expect(mirror).to have_received(:replace).with("OTHER-9", worklogs("9"), workflow: nil)
    end
  end
end
