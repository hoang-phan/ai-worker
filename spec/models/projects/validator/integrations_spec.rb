require "rails_helper"

RSpec.describe Projects::Validator do
  include ProjectsValidatorHelper

  describe "jira_base_url" do
    it "allows blank" do
      expect(project(jira_base_url: "")).to be_valid
    end

    it "must look like an Atlassian site URL" do
      errors = errors_for(project(jira_base_url: "http://bad"))

      expect(errors.details[:jira_base_url]).to eq([ { error: :invalid, value: "http://bad" } ])
      expect(errors[:jira_base_url]).to eq([ "must look like https://your-site.atlassian.net" ])
    end

    it "accepts https://site.atlassian.net" do
      expect(project(jira_base_url: "https://site.atlassian.net")).to be_valid
    end
  end

  describe "slack_review_channel" do
    it "allows blank" do
      expect(project(slack_review_channel: "")).to be_valid
    end

    it "must be a Slack channel ID" do
      errors = errors_for(project(slack_review_channel: "bad"))

      expect(errors.details[:slack_review_channel]).to eq([ { error: :invalid, value: "bad" } ])
      expect(errors[:slack_review_channel]).to eq([ "must be a Slack channel ID like C0B5XFY2F0T" ])
    end

    it "accepts a channel ID" do
      expect(project(slack_review_channel: "C0B5XFY2F0T")).to be_valid
    end
  end
end
