require "rails_helper"

RSpec.describe Workflows::Label do
  let(:jira_project) { Project.new(kind: :jira) }
  let(:personal_project) { Project.new(kind: :personal) }

  def build(project, **attrs)
    Workflow.new({ project: project, id: 42 }.merge(attrs))
  end

  def label(...)
    described_class.new(build(...))
  end

  describe "#to_s" do
    it "is the Jira ticket for a jira development workflow" do
      expect(label(jira_project, jira_ticket: "ABC-1").to_s).to eq("ABC-1")
    end

    it "is the task description for a personal development workflow" do
      expect(label(personal_project, task_description: "Fix the thing").to_s).to eq("Fix the thing")
    end

    it "is empty for a personal workflow without a task" do
      expect(label(personal_project).to_s).to eq("")
    end

    it "is org/repo#number for a pr_review workflow" do
      wf = label(jira_project, kind: :pr_review, github_pr_url: "https://github.com/org/repo/pull/7")
      expect(wf.to_s).to eq("org/repo#7")
    end

    it "is empty for a pr_review workflow with an unparseable url, while #value is nil" do
      wf = label(jira_project, kind: :pr_review, github_pr_url: "nope")
      expect(wf.to_s).to eq("")
      expect(wf.value).to be_nil
    end

    it "pr_review wins over a personal project" do
      wf = label(personal_project, kind: :pr_review, github_pr_url: "https://github.com/a/b/pull/1", task_description: "x")
      expect(wf.to_s).to eq("a/b#1")
    end

    it "joins non-blank runbook variable values" do
      wf = label(jira_project, kind: :runbook, variables: { "A" => "one", "B" => "", "C" => "two" })
      expect(wf.to_s).to eq("one · two")
    end

    it "truncates runbook variable values to 60 characters" do
      expect(label(jira_project, kind: :runbook, variables: { "A" => "x" * 100 }).to_s).to eq("x" * 57 + "...")
    end

    it "falls back to Run #id for a runbook with no variables" do
      expect(label(jira_project, kind: :runbook).to_s).to eq("Run #42")
      expect(label(jira_project, kind: :runbook, variables: { "A" => " " }).to_s).to eq("Run #42")
    end
  end

  describe "#brief" do
    it "prefers the summary over the label" do
      expect(label(jira_project, jira_ticket: "ABC-1", summary: "  Do   it ").brief).to eq("Do it")
    end

    it "falls back to the label" do
      expect(label(jira_project, jira_ticket: "ABC-1").brief).to eq("ABC-1")
    end

    it "truncates to Workflow::SUMMARY_LENGTH" do
      brief = label(jira_project, summary: "y" * 200).brief
      expect(brief.length).to eq(Workflow::SUMMARY_LENGTH)
      expect(brief).to end_with("...")
    end

    it "is empty when there is neither summary nor label" do
      expect(label(jira_project, kind: :pr_review).brief).to eq("")
    end
  end

  describe "#heading" do
    it "is the runbook label" do
      expect(label(jira_project, kind: :runbook, variables: { "A" => "one" }).heading).to eq("one")
    end

    it "prefixes pr_review with Review" do
      wf = label(jira_project, kind: :pr_review, github_pr_url: "https://github.com/org/repo/pull/7")
      expect(wf.heading).to eq("Review org/repo#7")
    end

    it "is Task #id for a personal project" do
      expect(label(personal_project, task_description: "Fix").heading).to eq("Task #42")
    end

    it "is the Jira ticket otherwise" do
      expect(label(jira_project, jira_ticket: "ABC-1").heading).to eq("ABC-1")
    end
  end
end
