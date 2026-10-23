require "rails_helper"

RSpec.describe BugsnagSyncJob, type: :job do
  # 2026-10-20 is a Tuesday.
  let(:tuesday_10am) { Time.zone.local(2026, 10, 20, 10, 0) }
  let(:dir) { Dir.mktmpdir("bugsnag-sync-job-spec") }
  let(:project) do
    build_jira_project(local_directory: dir)
  end
  let(:auto_sync) { true }
  let!(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "WEB", auto_sync: auto_sync) }
  let(:triager) { instance_double(Bugsnag::Triager, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:triage_sync) { instance_double(Bugsnag::TriageSync, triager: triager, blockers: blockers) }
  let(:blockers) { [] }

  before do
    allow(Bugsnag::TriageSync).to receive(:new).and_return(triage_sync)
    allow(Rails.logger).to receive(:warn)
  end

  after { FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir) }

  describe "importing a finished poll" do
    let(:rows) { [ { "id" => "e1" } ] }

    before { allow(triager).to receive(:poll).and_return(rows) }

    it "records the added tickets and sync time" do
      allow(triage_sync).to receive(:import).with(rows).and_return(Bugsnag::TriageSync::Result.new(added: %w[WEB-1 WEB-2]))
      travel_to(Time.zone.local(2026, 10, 20, 8, 0)) do
        described_class.perform_now
        expect(bugsnag_sync.reload.last_result).to eq("2 new ticket(s): WEB-1, WEB-2")
        expect(bugsnag_sync.last_synced_at).to eq(Time.current)
      end
    end

    it "records 'nothing new' when no tickets were added" do
      allow(triage_sync).to receive(:import).and_return(Bugsnag::TriageSync::Result.new(added: []))
      described_class.perform_now
      expect(bugsnag_sync.reload.last_result).to eq("nothing new")
    end
  end

  it "does not import or record when the poll has nothing finished" do
    expect(triage_sync).not_to receive(:import)
    travel_to(tuesday_10am) { described_class.perform_now }
    expect(bugsnag_sync.reload.last_result).to be_nil
  end

  describe "starting a new run" do
    def perform_at(time)
      travel_to(time) { described_class.perform_now }
    end

    it "starts on a weekday after RUN_HOUR when not started yet" do
      perform_at(tuesday_10am)
      expect(triager).to have_received(:start)
    end

    it "starts exactly at RUN_HOUR" do
      perform_at(tuesday_10am.change(hour: described_class::RUN_HOUR))
      expect(triager).to have_received(:start)
    end

    it "starts when the last run began on an earlier day" do
      allow(triager).to receive(:last_started_at).and_return(tuesday_10am.yesterday)
      perform_at(tuesday_10am)
      expect(triager).to have_received(:start)
    end

    it "does not start before RUN_HOUR" do
      perform_at(tuesday_10am.change(hour: described_class::RUN_HOUR - 1, min: 59))
      expect(triager).not_to have_received(:start)
    end

    it "does not start on Saturday or Sunday" do
      perform_at(Time.zone.local(2026, 10, 24, 10, 0))
      perform_at(Time.zone.local(2026, 10, 25, 10, 0))
      expect(triager).not_to have_received(:start)
    end

    it "does not start when a run already started today" do
      allow(triager).to receive(:last_started_at).and_return(tuesday_10am.change(hour: 9, min: 5))
      perform_at(tuesday_10am)
      expect(triager).not_to have_received(:start)
    end

    it "does not start while a run is in progress" do
      allow(triager).to receive(:running?).and_return(true)
      perform_at(tuesday_10am)
      expect(triager).not_to have_received(:start)
    end

    context "when auto_sync is off" do
      let(:auto_sync) { false }

      it "does not start" do
        perform_at(tuesday_10am)
        expect(triager).not_to have_received(:start)
      end
    end

    context "when blocked" do
      let(:blockers) { [ "local clone missing" ] }

      it "does not start and logs the blockers" do
        perform_at(tuesday_10am)
        expect(triager).not_to have_received(:start)
        expect(Rails.logger).to have_received(:warn).with("[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id} blocked: local clone missing")
      end
    end
  end

  describe "errors" do
    let!(:other_bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "api", jira_project: "API", auto_sync: true) }
    let(:other_triager) { instance_double(Bugsnag::Triager, poll: nil, running?: false, last_started_at: nil, start: nil) }
    let(:other_sync) { instance_double(Bugsnag::TriageSync, triager: other_triager, blockers: []) }

    before do
      allow(Rails.logger).to receive(:error)
      allow(Bugsnag::TriageSync).to receive(:new) { |s| s == bugsnag_sync ? triage_sync : other_sync }
    end

    it "records a FetchError and carries on with the next sync" do
      allow(triager).to receive(:poll).and_raise(Bugsnag::FetchError, "no result")
      travel_to(tuesday_10am) { described_class.perform_now }
      expect(bugsnag_sync.reload.last_result).to eq("failed: no result")
      expect(other_triager).to have_received(:start)
    end

    it "records an AiCli::CommandError and carries on with the next sync" do
      allow(triager).to receive(:start).and_raise(AiCli::CommandError, "claude exited 1")
      travel_to(tuesday_10am) { described_class.perform_now }
      expect(bugsnag_sync.reload.last_result).to eq("failed: claude exited 1")
      expect(other_triager).to have_received(:start)
    end
  end
end
