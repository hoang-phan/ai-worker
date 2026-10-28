require "rails_helper"

RSpec.describe TimeLogsHelper, type: :helper do
  describe "#logged_hours" do
    it "formats seconds as hours without insignificant zeros" do
      expect(helper.logged_hours(5400)).to eq("1.5")
      expect(helper.logged_hours(3600)).to eq("1")
      expect(helper.logged_hours(0)).to eq("0")
      expect(helper.logged_hours(1234)).to eq("0.34")
    end
  end

  describe "#workflow_logged_time_label" do
    let(:workflow) { build_jira_workflow(build_jira_project, jira_ticket: "TEST-1") }

    before do
      TimeLog.create!(workflow: workflow, ticket_key: workflow.jira_key, started_at: Time.current, seconds: 5400)
    end

    it "shows logged hours without a sync phrase when never synced" do
      expect(helper.workflow_logged_time_label(workflow)).to eq("1.5 h logged in Jira")
    end

    it "includes how long ago Jira hours were synced" do
      workflow.jira_logged_synced_at = 5.minutes.ago

      expect(helper.workflow_logged_time_label(workflow)).to eq("1.5 h logged in Jira — synced 5 minutes ago")
    end
  end

  describe "workflow row helpers" do
    let(:project) { build_jira_project }
    let(:workflow) { build_jira_workflow(project) }

    describe "#jira_synced_phrase" do
      it "is nil when never synced" do
        expect(helper.jira_synced_phrase(workflow)).to be_nil
      end

      it "says how long ago hours were synced" do
        workflow.jira_logged_synced_at = 5.minutes.ago
        expect(helper.jira_synced_phrase(workflow)).to eq("synced 5 minutes ago")
      end
    end

    describe "#workflow_logged_time_badge" do
      it "is nil for non-development workflows" do
        runbook = build_runbook_workflow(project)
        expect(helper.workflow_logged_time_badge(runbook, 3600)).to be_nil
      end

      it "shows Not logged without seconds" do
        expect(helper.workflow_logged_time_badge(workflow, nil)).to eq('<span class="badge badge-neutral">Not logged</span>')
      end

      it "shows hours with a plain title when never synced" do
        expect(helper.workflow_logged_time_badge(workflow, 5400)).to eq('<span class="badge badge-success" title="Hours you have logged in Jira">1.5 h</span>')
      end

      it "adds the synced phrase to the title" do
        workflow.jira_logged_synced_at = 2.hours.ago
        expect(helper.workflow_logged_time_badge(workflow, 3600)).to include('title="Hours you have logged in Jira, synced about 2 hours ago"')
      end
    end

    describe "#workflow_selection_data" do
      it "marks unlogged development rows as loggable and fresh" do
        expect(helper.workflow_selection_data(workflow, 0)).to include(log_time: true, fresh: true)
        expect(helper.workflow_selection_data(workflow, nil)).to include(fresh: true)
      end

      it "keeps logged development rows loggable but not fresh" do
        expect(helper.workflow_selection_data(workflow, 3600)).to include(log_time: true, fresh: false)
      end

      it "marks non-development rows as unable to log time" do
        allow(workflow).to receive(:development?).and_return(false)
        expect(helper.workflow_selection_data(workflow, 0)).to include(log_time: false, fresh: false)
      end
    end
  end
end
