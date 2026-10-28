require "rails_helper"

RSpec.describe Projects::Validator do
  include ProjectsValidatorHelper

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
