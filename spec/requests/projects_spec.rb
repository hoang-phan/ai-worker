require "rails_helper"

RSpec.describe "Projects", type: :request do
  let(:local_directory) { Dir.mktmpdir("projects-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "POST sync_slack" do
    let(:fetcher) { instance_double(Slack::MentionFetcher, start: true) }
    let(:sync) { instance_double(Slack::ReviewSync, blockers: [], fetcher: fetcher) }

    before { allow(Slack::ReviewSync).to receive(:new).and_return(sync) }

    it "reports the blockers" do
      allow(sync).to receive(:blockers).and_return([ "no channel", "no mention" ])

      post sync_slack_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Slack sync blocked: no channel; no mention")
      expect(fetcher).not_to have_received(:start)
    end

    it "starts the fetch" do
      post sync_slack_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing.")
    end

    it "says when a fetch is already running" do
      allow(fetcher).to receive(:start).and_return(false)

      post sync_slack_project_path(project)

      expect(flash[:alert]).to eq("A Slack fetch is already running for this project.")
    end

    it "reports a failed start" do
      allow(fetcher).to receive(:start).and_raise(AiCli::CommandError, "claude exploded")

      post sync_slack_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Slack sync failed: claude exploded")
    end
  end

  describe "POST brainstorm" do
    let(:planner) { instance_double(Brainstorm::Planner, blockers: [], queued_count: 0, start: true) }

    before { allow(Brainstorm::Planner).to receive(:new).and_return(planner) }

    it "reports the blockers" do
      allow(planner).to receive(:blockers).and_return([ "brainstorm is off" ])

      post brainstorm_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Brainstorm blocked: brainstorm is off")
      expect(planner).not_to have_received(:start)
    end

    it "skips while workflows are pending" do
      allow(planner).to receive(:queued_count).and_return(2)

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("Brainstorm skipped: 2 workflow(s) still pending; start or delete them first.")
      expect(planner).not_to have_received(:start)
    end

    it "starts a brainstorm and records the run time" do
      post brainstorm_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Agent is brainstorming workflows. They appear within the hour after it finishes.")
      expect(project.reload.brainstorm_last_run_at).to be_present
    end

    it "says when a brainstorm is already running" do
      allow(planner).to receive(:start).and_return(false)

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("A brainstorm is already running for this project.")
    end

    it "reports a failed start" do
      allow(planner).to receive(:start).and_raise(AiCli::CommandError, "claude exploded")

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("Brainstorm failed: claude exploded")
    end
  end
end
