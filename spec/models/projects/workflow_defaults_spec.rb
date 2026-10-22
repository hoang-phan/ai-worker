require "rails_helper"

RSpec.describe Projects::WorkflowDefaults do
  let(:local_directory) { Dir.mktmpdir("workflow-defaults-spec") }
  let(:project) do
    Project.create!(name: "Defaults spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory,
                    default_skills: "skill-a", default_pr_skills: "pr-skill", default_reviewers: "alice")
  end

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe ".kind_for" do
    it "returns :runbook for runbook strings and symbols" do
      expect(described_class.kind_for("runbook")).to eq(:runbook)
      expect(described_class.kind_for(:runbook)).to eq(:runbook)
    end

    it "falls back to :development for anything else" do
      [ nil, "", "development", "pr_review", "bogus" ].each do |value|
        expect(described_class.kind_for(value)).to eq(:development)
      end
    end
  end

  describe "#attributes" do
    it "prefills development workflows from the project" do
      expect(described_class.new(project).attributes(kind: :development)).to eq(
        position: 1, skills: "skill-a", pr_skills: "pr-skill", github_reviewer: "alice", kind: :development
      )
    end

    it "gives runbooks the same prefill with the runbook kind" do
      expect(described_class.new(project).attributes(kind: "runbook")).to include(position: 1, skills: "skill-a", kind: :runbook)
    end

    it "normalises unknown or nil kinds to development" do
      expect(described_class.new(project).attributes(kind: "nope")[:kind]).to eq(:development)
      expect(described_class.new(project).attributes(kind: nil)[:kind]).to eq(:development)
    end

    it "keeps blank project defaults blank" do
      bare = Project.create!(name: "Defaults bare project", kind: :jira, repo_full_name: "org/bare", local_directory: local_directory)
      attrs = described_class.new(bare).attributes(kind: :development)
      expect(attrs.values_at(:skills, :pr_skills, :github_reviewer)).to all(be_blank)
    end

    it "puts the position after existing workflows" do
      project.workflows.create!(jira_ticket: "DEFAULTS-1", branch_name: "defaults-1", github_reviewer: "x", position: 4)
      expect(described_class.new(project).attributes[:position]).to eq(5)
    end
  end
end
