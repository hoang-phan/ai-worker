require "rails_helper"

RSpec.describe Workflows::Validator do
  let_tmpdir(:local_directory, "workflow-validator-spec")
  let(:jira_project) { build_jira_project(repo_full_name: "org/repo", local_directory: local_directory) }
  let(:personal_project) { build_personal_project(local_directory: local_directory) }
  let(:pr_url) { "https://github.com/org/repo/pull/7" }

  def errors_for(workflow)
    workflow.valid?
    workflow.errors
  end

  describe "jira development workflows" do
    it "is valid with a ticket, branch and reviewer" do
      expect(jira_project.workflows.build(jira_ticket: "V-1", branch_name: "v-1", github_reviewer: "octocat")).to be_valid
    end

    %i[jira_ticket branch_name github_reviewer].each do |attribute|
      it "requires #{attribute}" do
        workflow = jira_project.workflows.build(jira_ticket: "V-1", branch_name: "v-1", github_reviewer: "octocat", attribute => " ")

        expect(errors_for(workflow).details[attribute]).to eq([ { error: :blank } ])
      end
    end
  end

  describe "personal development workflows" do
    it "requires task_description" do
      expect(errors_for(personal_project.workflows.build).details[:task_description]).to eq([ { error: :blank } ])
    end

    it "does not require the Jira fields" do
      expect(errors_for(personal_project.workflows.build(task_description: "Do it")).attribute_names).to be_empty
    end
  end

  describe "pr_review workflows" do
    it "requires github_pr_url" do
      expect(errors_for(jira_project.workflows.build(kind: :pr_review)).details[:github_pr_url]).to eq([ { error: :blank } ])
    end

    it "is valid on a Jira project with a PR url" do
      expect(jira_project.workflows.build(kind: :pr_review, github_pr_url: pr_url)).to be_valid
    end

    it "rejects a personal project" do
      errors = errors_for(personal_project.workflows.build(kind: :pr_review, github_pr_url: pr_url))

      expect(errors[:base]).to eq([ "PR reviews need a Jira (GitHub-backed) project" ])
    end

    it "rejects a missing project without raising" do
      errors = errors_for(Workflow.new(kind: :pr_review, github_pr_url: pr_url))

      expect(errors[:base]).to include("PR reviews need a Jira (GitHub-backed) project")
    end

    it "keeps the github_pr_url format check on the model" do
      errors = errors_for(jira_project.workflows.build(kind: :pr_review, github_pr_url: "https://example.com/x"))

      expect(errors[:github_pr_url]).to eq([ "must be a github.com pull request URL" ])
    end
  end

  describe "workflows without a project" do
    it "skips the project-kind rules for development workflows" do
      expect(errors_for(Workflow.new).attribute_names).to eq([ :project ])
    end
  end

  describe "variable names" do
    it "rejects names that are not placeholders" do
      workflow = jira_project.workflows.build(kind: :runbook, variables: { "OK_1" => "a", "bad-name" => "b", "also bad" => "c" })

      expect(errors_for(workflow)[:variables]).to eq([ "names must be letters, digits or underscores (bad-name, also bad)" ])
    end

    it "accepts letters, digits and underscores" do
      expect(jira_project.workflows.build(kind: :runbook, variables: { "CHANNEL_2" => "#ops" })).to be_valid
    end
  end

  describe "copy_stages_from_id" do
    let!(:source) { build_runbook_workflow(jira_project) }

    it "accepts a runbook of the same project" do
      expect(jira_project.workflows.build(kind: :runbook, copy_stages_from_id: source.id)).to be_valid
    end

    it "is ignored when blank" do
      expect(jira_project.workflows.build(kind: :runbook, copy_stages_from_id: "")).to be_valid
    end

    it "rejects a runbook of another project" do
      other = build_runbook_workflow(build_jira_project(repo_full_name: "org/other", local_directory: local_directory))

      expect(errors_for(jira_project.workflows.build(kind: :runbook, copy_stages_from_id: other.id))[:copy_stages_from_id])
        .to eq([ "must be a runbook workflow of this project" ])
    end

    it "rejects a workflow that is not a runbook" do
      development = build_jira_workflow(jira_project)

      expect(errors_for(jira_project.workflows.build(kind: :runbook, copy_stages_from_id: development.id))[:copy_stages_from_id])
        .to eq([ "must be a runbook workflow of this project" ])
    end

    it "is not checked for non-runbook workflows" do
      workflow = jira_project.workflows.build(jira_ticket: "V-2", branch_name: "v-2", github_reviewer: "o", copy_stages_from_id: 0)

      expect(workflow).to be_valid
    end
  end

  describe "reusing one validator instance" do
    let(:validator) { described_class.new }

    def validate_with(validator, workflow)
      validator.validate(workflow)
      workflow.errors
    end

    it "keeps errors on the intended record across sequential invocations" do
      invalid = personal_project.workflows.build
      valid = personal_project.workflows.build(task_description: "Do it")

      validate_with(validator, invalid)
      validate_with(validator, valid)

      expect(invalid.errors.details[:task_description]).to eq([ { error: :blank } ])
      expect(valid.errors).to be_empty
    end

    it "does not retain the workflow between invocations" do
      validator.validate(personal_project.workflows.build)

      expect(validator.instance_variables).to eq([ :@options ])
    end

    it "keeps errors on each record when re-entered for a second record mid-validation" do
      outer = jira_project.workflows.build(jira_ticket: "V-1", branch_name: "v-1", github_reviewer: "octocat", kind: :runbook)
      outer.variables = { "bad-name" => "x" }
      inner = personal_project.workflows.build
      reentered = false
      allow(outer).to receive(:runbook?).and_wrap_original do |original|
        unless reentered
          reentered = true
          validator.validate(inner)
        end
        original.call
      end

      validator.validate(outer)

      expect(reentered).to be(true)
      expect(inner.errors.attribute_names).to eq([ :task_description ])
      expect(outer.errors.attribute_names).to eq([ :variables ])
    end
  end
end
