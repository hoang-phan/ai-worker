require "rails_helper"

RSpec.describe Projects::Validator do
  include ProjectsValidatorHelper

  describe "ci_command" do
    it "is required for the ci_loop flow" do
      errors = errors_for(project(kind: :jira, repo_full_name: "org/repo", flow: :ci_loop, ci_command: ""))

      expect(errors.details[:ci_command]).to eq([ { error: :blank } ])
      expect(errors[:ci_command]).to eq([ "is required for the ci_loop flow" ])
    end

    it "is not required for the standard flow" do
      expect(errors_for(project(kind: :jira, repo_full_name: "org/repo", flow: :standard, ci_command: ""))
               .attribute_names).not_to include(:ci_command)
    end

    it "accepts a command on ci_loop" do
      expect(project(kind: :jira, repo_full_name: "org/repo", flow: :ci_loop, ci_command: "bin/ci")).to be_valid
    end
  end

  describe "ci_max_rounds" do
    it "must be greater than 0" do
      expect(errors_for(project(ci_max_rounds: 0)).details[:ci_max_rounds])
        .to eq([ { error: :greater_than, value: 0, count: 0 } ])
    end

    it "must be at most 20" do
      expect(errors_for(project(ci_max_rounds: 21)).details[:ci_max_rounds])
        .to eq([ { error: :less_than_or_equal_to, value: 21, count: 20 } ])
    end

    it "rejects a non-number" do
      expect(errors_for(project(ci_max_rounds: "x")).details[:ci_max_rounds])
        .to eq([ { error: :not_a_number, value: "x" } ])
    end

    it "accepts a value in range" do
      expect(project(ci_max_rounds: 5)).to be_valid
    end
  end

  describe "brainstorm_goal" do
    it "is required when brainstorm is enabled" do
      expect(errors_for(project(brainstorm_enabled: true, brainstorm_goal: "")).details[:brainstorm_goal])
        .to eq([ { error: :blank } ])
    end

    it "is not required when brainstorm is off" do
      expect(errors_for(project(brainstorm_enabled: false, brainstorm_goal: "")).attribute_names)
        .not_to include(:brainstorm_goal)
    end

    it "accepts a goal when brainstorm is enabled" do
      expect(project(brainstorm_enabled: true, brainstorm_goal: "Ship it")).to be_valid
    end
  end

  describe "brainstorm_max_workflows" do
    it "must be greater than 0" do
      expect(errors_for(project(brainstorm_max_workflows: 0)).details[:brainstorm_max_workflows])
        .to eq([ { error: :greater_than, value: 0, count: 0 } ])
    end

    it "must be at most 20" do
      expect(errors_for(project(brainstorm_max_workflows: 21)).details[:brainstorm_max_workflows])
        .to eq([ { error: :less_than_or_equal_to, value: 21, count: 20 } ])
    end

    it "accepts a value in range" do
      expect(project(brainstorm_max_workflows: 3)).to be_valid
    end
  end
end
