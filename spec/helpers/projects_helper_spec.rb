require "rails_helper"

RSpec.describe ProjectsHelper, type: :helper do
  describe "#project_header_meta" do
    it "joins the directory and repo name" do
      project = build_jira_project(local_directory: "/tmp/x", repo_full_name: "acme/widgets")

      expect(helper.project_header_meta(project)).to eq("/tmp/x · acme/widgets")
    end

    it "omits the separator when there is no repo name" do
      project = build_personal_project(local_directory: "/tmp/x")

      expect(helper.project_header_meta(project)).to eq("/tmp/x")
    end

    it "escapes HTML in the repo name" do
      project = build_jira_project(repo_full_name: "acme/<b>x")
      meta = helper.project_header_meta(project)

      expect(meta).to include("&lt;b&gt;x")
      expect(meta).not_to include("<b>")
    end
  end

  describe "#show_brainstorm_section?" do
    it "requires a personal project with brainstorm enabled or a goal" do
      expect(helper.show_brainstorm_section?(build_personal_project)).to be false
      expect(helper.show_brainstorm_section?(build_personal_project(brainstorm_enabled: true, brainstorm_goal: "Ship it"))).to be true
      expect(helper.show_brainstorm_section?(build_personal_project(brainstorm_goal: "Ship it"))).to be true
      expect(helper.show_brainstorm_section?(build_jira_project(brainstorm_goal: "Ship it"))).to be false
    end
  end

  describe "#show_slack_reviews_section?" do
    it "requires a jira project with slack reviews enabled or a mention" do
      expect(helper.show_slack_reviews_section?(build_jira_project)).to be false
      expect(helper.show_slack_reviews_section?(build_jira_project(slack_review_enabled: true))).to be true
      expect(helper.show_slack_reviews_section?(build_jira_project(slack_mention: "@me"))).to be true
      expect(helper.show_slack_reviews_section?(build_personal_project(slack_mention: "@me"))).to be false
    end
  end

  describe "#workflow_status_filter_options" do
    it "lists all workflow statuses after the unfiltered option" do
      expect(helper.workflow_status_filter_options).to eq(
        [ [ "All", "" ] ] + Workflow.statuses.keys.map { |status| [ status.humanize, status ] }
      )
    end
  end

  describe "#workflow_list_empty_message" do
    it "returns the unfiltered empty-state message" do
      workflow_list = instance_double(Projects::WorkflowList, status_filter: nil)

      expect(helper.workflow_list_empty_message(workflow_list)).to eq("No workflows yet.")
    end

    it "returns the filtered empty-state message" do
      workflow_list = instance_double(Projects::WorkflowList, status_filter: "uat_waiting")

      expect(helper.workflow_list_empty_message(workflow_list)).to eq("No uat waiting workflows.")
    end
  end

  describe "#icon_svg" do
    it "renders the external-link icon exactly" do
      expect(helper.icon_svg(:external_link)).to eq(
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 3h7v7h-2V6.41l-9.29 9.3-1.42-1.42L17.59 5H14V3Zm5 16H5V5h7V3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7h-2v7Z"/></svg>'
      )
    end

    it "renders the edit icon exactly" do
      expect(helper.icon_svg(:edit)).to eq(
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25ZM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83Z"/></svg>'
      )
    end
  end
end
