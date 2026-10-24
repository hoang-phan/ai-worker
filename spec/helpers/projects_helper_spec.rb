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
end
