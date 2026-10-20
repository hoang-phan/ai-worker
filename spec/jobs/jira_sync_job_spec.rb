require "rails_helper"

RSpec.describe JiraSyncJob, type: :job do
  let(:dir) { Dir.mktmpdir("jira-sync-job-spec") }
  let(:base_url) { "https://acme.atlassian.net" }
  let(:project) do
    Project.create!(name: "JiraSyncJob spec #{SecureRandom.hex(4)}", kind: :jira, local_directory: dir, repo_full_name: "acme/widgets",
                    jira_base_url: base_url)
  end
  let(:auto_sync) { true }
  let!(:jira_sync) { project.jira_syncs.create!(auto_sync: auto_sync) }
  let(:fetcher) { instance_double(Jira::AgentFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:blockers) { [] }
  let(:ticket_sync) { instance_double(Jira::TicketSync, fetcher: fetcher, blockers: blockers) }
  let(:result) { Jira::TicketSync::Result.new(blockers: [], created: %w[A-1 A-2], skipped: [ "A-3" ], failed: []) }

  before do
    allow(Jira::TicketSync).to receive(:new).and_return(ticket_sync)
    allow(Rails.logger).to receive(:warn)
  end

  after { FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir) }

  describe "importing a finished poll" do
    let(:issues) { [ { "key" => "A-1" } ] }

    before do
      allow(fetcher).to receive(:poll).and_return(issues)
      allow(ticket_sync).to receive(:import).with(issues).and_return(result)
    end

    it "records the summary and sync time" do
      freeze_time do
        described_class.perform_now
        expect(jira_sync.reload.last_result).to eq("created 2, skipped 1, failed 0")
        expect(jira_sync.last_synced_at).to eq(Time.current)
      end
    end
  end

  it "does not import or record when the poll has nothing finished" do
    expect(ticket_sync).not_to receive(:import)
    described_class.perform_now
    expect(jira_sync.reload.last_result).to be_nil
  end

  describe "starting a new fetch" do
    it "starts when auto_sync is on, idle and never started" do
      described_class.perform_now
      expect(fetcher).to have_received(:start)
    end

    it "starts when the last start is older than FETCH_EVERY" do
      allow(fetcher).to receive(:last_started_at).and_return((described_class::FETCH_EVERY + 1.minute).ago)
      described_class.perform_now
      expect(fetcher).to have_received(:start)
    end

    it "does not start when the last start is within FETCH_EVERY" do
      allow(fetcher).to receive(:last_started_at).and_return((described_class::FETCH_EVERY - 1.minute).ago)
      described_class.perform_now
      expect(fetcher).not_to have_received(:start)
    end

    it "does not start while a fetch is running" do
      allow(fetcher).to receive(:running?).and_return(true)
      described_class.perform_now
      expect(fetcher).not_to have_received(:start)
    end

    context "when auto_sync is off" do
      let(:auto_sync) { false }

      it "does not start" do
        described_class.perform_now
        expect(fetcher).not_to have_received(:start)
      end
    end

    context "when the project has no jira_base_url" do
      let(:base_url) { nil }

      it "skips the sync entirely" do
        described_class.perform_now
        expect(Jira::TicketSync).not_to have_received(:new)
      end
    end

    context "when blocked" do
      let(:blockers) { [ "Jira base URL missing", "no assignee" ] }

      it "does not start and logs the blockers" do
        described_class.perform_now
        expect(fetcher).not_to have_received(:start)
        expect(Rails.logger).to have_received(:warn).with("[JiraSyncJob] jira_sync=#{jira_sync.id} blocked: Jira base URL missing; no assignee")
      end
    end
  end

  describe "errors" do
    let(:other_sync) { project.jira_syncs.create!(auto_sync: true) }
    let(:other_fetcher) { instance_double(Jira::AgentFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
    let(:other_ticket_sync) { instance_double(Jira::TicketSync, fetcher: other_fetcher, blockers: []) }

    before do
      allow(Rails.logger).to receive(:error)
      other_sync
      allow(Jira::TicketSync).to receive(:new).with(jira_sync).and_return(ticket_sync)
      allow(Jira::TicketSync).to receive(:new).with(other_sync).and_return(other_ticket_sync)
    end

    it "records a FetchError and carries on with the next sync" do
      allow(fetcher).to receive(:poll).and_raise(Jira::FetchError, "bad json")
      described_class.perform_now
      expect(jira_sync.reload.last_result).to eq("failed: bad json")
      expect(other_fetcher).to have_received(:start)
    end

    it "records an AiCli::CommandError and carries on with the next sync" do
      allow(fetcher).to receive(:start).and_raise(AiCli::CommandError, "claude exited 1")
      described_class.perform_now
      expect(jira_sync.reload.last_result).to eq("failed: claude exited 1")
      expect(other_fetcher).to have_received(:start)
    end
  end
end
