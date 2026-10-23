require "rails_helper"

RSpec.describe SlackReviewJob, type: :job do
  let(:dirs) { [] }
  let(:fetcher) { instance_double(Slack::MentionFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:blockers) { [] }
  let(:review_sync) { instance_double(Slack::ReviewSync, fetcher: fetcher, blockers: blockers) }
  let(:enabled) { true }
  let!(:project) { create_project(slack_review_enabled: enabled) }

  def create_project(**attrs)
    dir = Dir.mktmpdir("slack-review-job-spec")
    dirs << dir
    build_jira_project(**{ local_directory: dir }.merge(attrs))
  end

  def sync_result(created: [], skipped: [], failed: [], skipped_reasons: Hash.new(0))
    Slack::ReviewSync::Result.new(blockers: [], created: created, skipped: skipped, failed: failed, skipped_reasons: skipped_reasons)
  end

  before do
    allow(Slack::ReviewSync).to receive(:new).and_return(review_sync)
    allow(Rails.logger).to receive(:warn)
    allow(WorkflowSchedulerJob).to receive(:perform_later)
  end

  after { dirs.each { |d| FileUtils.remove_entry(d) if d.start_with?(Dir.tmpdir) && File.exist?(d) } }

  describe "importing a finished poll" do
    let(:mentions) { [ { "url" => "x" } ] }

    before { allow(fetcher).to receive(:poll).and_return(mentions) }

    it "records the summary with skip reasons, and enqueues the scheduler when workflows were created" do
      result = sync_result(created: [ 1 ], skipped: [ 2, 3 ], failed: [ 4 ], skipped_reasons: { "not our repo" => 2 })
      allow(review_sync).to receive(:import).with(mentions).and_return(result)

      freeze_time do
        described_class.perform_now
        project.reload
        expect(project.slack_last_result).to eq("created 1, skipped 2 (2 not our repo), failed 1")
        expect(project.slack_last_synced_at).to eq(Time.current)
      end
      expect(WorkflowSchedulerJob).to have_received(:perform_later).once
    end

    it "omits the reason list when nothing was skipped" do
      allow(review_sync).to receive(:import).and_return(sync_result)
      described_class.perform_now
      expect(project.reload.slack_last_result).to eq("created 0, skipped 0, failed 0")
    end

    it "does not enqueue the scheduler when no workflows were created" do
      allow(review_sync).to receive(:import).and_return(sync_result(skipped: [ 1 ]))
      described_class.perform_now
      expect(WorkflowSchedulerJob).not_to have_received(:perform_later)
    end
  end

  it "does not import or record when the poll has nothing finished" do
    expect(review_sync).not_to receive(:import)
    described_class.perform_now
    expect(project.reload.slack_last_result).to be_nil
  end

  describe "projects considered" do
    let(:enabled) { false }

    it "ignores projects with Slack reviews disabled" do
      described_class.perform_now
      expect(Slack::ReviewSync).not_to have_received(:new)
    end

    it "ignores personal projects" do
      create_project(kind: :personal, repo_full_name: nil, slack_review_enabled: true)
      described_class.perform_now
      expect(Slack::ReviewSync).not_to have_received(:new)
    end
  end

  describe "starting a new fetch" do
    it "starts when idle and never started" do
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

    context "when blocked" do
      let(:blockers) { [ "no channel" ] }

      it "does not start and logs the blockers" do
        described_class.perform_now
        expect(fetcher).not_to have_received(:start)
        expect(Rails.logger).to have_received(:warn).with("[SlackReviewJob] project=#{project.id} blocked: no channel")
      end
    end
  end

  describe "errors" do
    let!(:other) { create_project(slack_review_enabled: true) }
    let(:other_fetcher) { instance_double(Slack::MentionFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
    let(:other_review_sync) { instance_double(Slack::ReviewSync, fetcher: other_fetcher, blockers: []) }

    before do
      allow(Rails.logger).to receive(:error)
      allow(Slack::ReviewSync).to receive(:new) { |p| p == project ? review_sync : other_review_sync }
    end

    it "records a FetchError and carries on with the next project" do
      allow(fetcher).to receive(:poll).and_raise(Slack::FetchError, "slack down")
      described_class.perform_now
      expect(project.reload.slack_last_result).to eq("failed: slack down")
      expect(other_fetcher).to have_received(:start)
    end

    it "records an AiCli::CommandError and carries on with the next project" do
      allow(fetcher).to receive(:start).and_raise(AiCli::CommandError, "claude exited 1")
      described_class.perform_now
      expect(project.reload.slack_last_result).to eq("failed: claude exited 1")
      expect(other_fetcher).to have_received(:start)
    end
  end
end
