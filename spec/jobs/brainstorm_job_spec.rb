require "rails_helper"

RSpec.describe BrainstormJob, type: :job do
  let(:dirs) { [] }
  let(:state_root) { Dir.mktmpdir("brainstorm-job-state").tap { |d| dirs << d } }
  let(:planner) { Brainstorm::Planner.new(project, root: state_root) }
  let(:blockers) { [] }
  let(:enabled) { true }
  let!(:project) { create_project(brainstorm_enabled: enabled) }

  def create_project(**attrs)
    dir = Dir.mktmpdir("brainstorm-job-spec")
    dirs << dir
    build_personal_project(**{ local_directory: dir, brainstorm_goal: "ship it" }.merge(attrs))
  end

  before do
    allow(planner).to receive_messages(poll: nil, running?: false, queued_count: 0, blockers: blockers, start: nil)
    allow(Brainstorm::Planner).to receive(:new).and_return(planner)
    allow(Rails.logger).to receive(:warn)
  end

  after { dirs.each { |d| FileUtils.remove_entry(d) if d.start_with?(Dir.tmpdir) && File.exist?(d) } }

  describe "importing a finished poll" do
    let(:proposals) { [ { "title" => "x" } ] }

    it "records the summary" do
      allow(planner).to receive(:poll).and_return(proposals)
      allow(planner).to receive(:import).with(proposals).and_return(Brainstorm::Planner::Result.new(created: [ 1, 2 ], skipped: [ 3 ]))
      described_class.perform_now
      expect(project.reload.brainstorm_last_result).to eq("created 2, skipped 1")
    end

    it "does not import or record when the poll has nothing finished" do
      expect(planner).not_to receive(:import)
      described_class.perform_now
      expect(project.reload.brainstorm_last_result).to be_nil
    end
  end

  describe "projects considered" do
    let(:enabled) { false }

    it "ignores projects with brainstorming off" do
      described_class.perform_now
      expect(Brainstorm::Planner).not_to have_received(:new)
    end

    it "ignores jira projects" do
      create_project(kind: :jira, repo_full_name: "acme/widgets", brainstorm_enabled: true)
      described_class.perform_now
      expect(Brainstorm::Planner).not_to have_received(:new)
    end
  end

  describe "starting a new run" do
    it "starts and sets brainstorm_last_run_at when idle with no queued workflows" do
      freeze_time do
        described_class.perform_now
        expect(planner).to have_received(:start)
        expect(project.reload.brainstorm_last_run_at).to eq(Time.current)
      end
    end

    it "does not start while a run is in progress" do
      allow(planner).to receive(:running?).and_return(true)
      described_class.perform_now
      expect(planner).not_to have_received(:start)
      expect(project.reload.brainstorm_last_run_at).to be_nil
    end

    it "does not start while workflows are queued" do
      allow(planner).to receive(:queued_count).and_return(2)
      described_class.perform_now
      expect(planner).not_to have_received(:start)
      expect(project.reload.brainstorm_last_run_at).to be_nil
    end

    context "when blocked" do
      let(:blockers) { [ "no goal" ] }

      it "does not start and logs the blockers" do
        described_class.perform_now
        expect(planner).not_to have_received(:start)
        expect(project.reload.brainstorm_last_run_at).to be_nil
        expect(Rails.logger).to have_received(:warn).with("[BrainstormJob] project=#{project.id} blocked: no goal")
      end
    end
  end

  describe "errors" do
    let!(:other) { create_project(brainstorm_enabled: true) }
    let(:other_planner) { instance_double(Brainstorm::Planner, poll: nil, running?: false, wait_reason: nil, blockers: [], start: nil, record_start!: true) }

    before do
      allow(Rails.logger).to receive(:error)
      allow(Brainstorm::Planner).to receive(:new) { |p| p == project ? planner : other_planner }
    end

    it "records a FetchError and carries on with the next project" do
      allow(planner).to receive(:poll).and_raise(Brainstorm::FetchError, "no result")
      described_class.perform_now
      expect(project.reload.brainstorm_last_result).to eq("failed: no result")
      expect(other_planner).to have_received(:start)
    end

    it "records an AiCli::CommandError and carries on with the next project" do
      allow(planner).to receive(:start).and_raise(AiCli::CommandError, "claude exited 1")
      described_class.perform_now
      expect(project.reload.brainstorm_last_result).to eq("failed: claude exited 1")
      expect(other_planner).to have_received(:start)
    end
  end
end
