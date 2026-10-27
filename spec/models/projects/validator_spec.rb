require "rails_helper"

RSpec.describe Projects::Validator do
  let_tmpdir(:local_directory, "project-validator-spec")

  def project(**attrs)
    Project.new({ name: "Spec project", kind: :personal, local_directory: local_directory }.merge(attrs))
  end

  def errors_for(record)
    record.valid?
    record.errors
  end

  describe "local_directory" do
    it "is valid with a separate clone" do
      expect(project).to be_valid
    end

    it "requires presence" do
      expect(errors_for(project(local_directory: "")).details[:local_directory]).to eq([ { error: :blank } ])
    end

    it "rejects the running app's live checkout" do
      errors = errors_for(project(local_directory: Rails.root.to_s))

      expect(errors[:local_directory]).to eq(
        [ "is this app's own live checkout; use a separate clone (see docs/ADDING_A_PROJECT.md)" ]
      )
    end
  end

  describe "repo_full_name" do
    it "is required for Jira projects" do
      expect(errors_for(project(kind: :jira, repo_full_name: "")).details[:repo_full_name])
        .to include({ error: :blank })
    end

    it "must be org/repo for Jira projects" do
      expect(errors_for(project(kind: :jira, repo_full_name: "bad")).details[:repo_full_name])
        .to eq([ { error: :invalid, value: "bad" } ])
      expect(errors_for(project(kind: :jira, repo_full_name: "bad"))[:repo_full_name])
        .to eq([ "must be in the form org/repo" ])
    end

    it "accepts org/repo for Jira projects" do
      expect(project(kind: :jira, repo_full_name: "org/repo")).to be_valid
    end

    it "is not required for personal projects" do
      expect(errors_for(project(kind: :personal, repo_full_name: nil)).attribute_names).not_to include(:repo_full_name)
    end
  end

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

  describe "uat_url" do
    it "allows blank when UAT testing is off" do
      expect(project(uat_url: "", uat_test_enabled: false)).to be_valid
    end

    it "must be a full HTTP URL" do
      errors = errors_for(project(uat_url: "not-a-url"))

      expect(errors.details[:uat_url]).to eq([ { error: :invalid, value: "not-a-url" } ])
      expect(errors[:uat_url]).to eq([ "must be a full URL like https://uat.example.com" ])
    end

    it "is required when UAT testing is enabled" do
      expect(errors_for(project(uat_test_enabled: true, uat_url: "")).details[:uat_url])
        .to eq([ { error: :blank } ])
    end

    it "accepts a full URL when UAT testing is enabled" do
      expect(project(uat_test_enabled: true, uat_url: "https://uat.example.com")).to be_valid
    end
  end

  describe "local_url" do
    it "allows blank when local testing is off" do
      expect(project(local_url: "", local_test_enabled: false)).to be_valid
    end

    it "must be a full HTTP URL" do
      errors = errors_for(project(local_url: "ftp://x"))

      expect(errors.details[:local_url]).to eq([ { error: :invalid, value: "ftp://x" } ])
      expect(errors[:local_url]).to eq([ "must be a full URL like http://localhost:3000" ])
    end

    it "is required when local testing is enabled" do
      expect(errors_for(project(local_test_enabled: true, local_url: "")).details[:local_url])
        .to eq([ { error: :blank } ])
    end

    it "accepts a full URL when local testing is enabled" do
      expect(project(local_test_enabled: true, local_url: "http://localhost:3000")).to be_valid
    end
  end

  describe "uat_test_delay_minutes" do
    it "rejects a negative value" do
      expect(errors_for(project(uat_test_delay_minutes: -1)).details[:uat_test_delay_minutes])
        .to eq([ { error: :greater_than_or_equal_to, value: -1, count: 0 } ])
    end

    it "accepts zero" do
      expect(project(uat_test_delay_minutes: 0)).to be_valid
    end
  end

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

  describe "flow needs Jira" do
    it "rejects ci_loop on a personal project" do
      errors = errors_for(project(kind: :personal, flow: :ci_loop, ci_command: "bin/ci"))

      expect(errors.details[:flow]).to eq([ { error: :inclusion, value: "ci_loop" } ])
      expect(errors[:flow]).to eq([ "ci_loop needs a Jira project" ])
    end

    it "allows ci_loop on a Jira project" do
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

  describe "reusing one validator instance" do
    let(:validator) { described_class.new }

    def validate_with(validator, record)
      validator.validate(record)
      record.errors
    end

    it "keeps errors on the intended record across sequential invocations" do
      invalid = project(local_directory: "")
      valid = project

      validate_with(validator, invalid)
      validate_with(validator, valid)

      expect(invalid.errors.details[:local_directory]).to eq([ { error: :blank } ])
      expect(valid.errors).to be_empty
    end

    it "does not retain the project between invocations" do
      validator.validate(project)

      expect(validator.instance_variables).to eq([ :@options ])
    end
  end
end
