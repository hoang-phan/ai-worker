require "rails_helper"

RSpec.describe Jira::TicketSync do
  let_tmpdir(:dir, "ticket-sync-spec")
  let(:project) do
    build_jira_project(local_directory: dir, jira_base_url: "https://acme.atlassian.net", jira_assignee: "me@example.com",
                    default_reviewers: "alice,bob", default_skills: "rails,testing")
  end
  let(:jira_sync) { project.jira_syncs.create! }
  let(:sync) { described_class.new(jira_sync) }


  describe "#blockers" do
    it "is empty for a fully configured project" do
      expect(sync.blockers).to be_empty
    end

    it "lists every missing prerequisite" do
      project.update_columns(kind: Project.kinds[:personal], jira_base_url: nil, jira_assignee: nil, default_reviewers: nil)

      expect(sync.blockers).to contain_exactly(
        "project kind is not jira",
        "Jira site URL is not set",
        "assignee is not set",
        "default GitHub reviewers are not set (workflows require a reviewer)"
      )
    end
  end

  describe "#fetcher" do
    it "returns the injected fetcher" do
      fetcher = double("fetcher")

      expect(described_class.new(jira_sync, fetcher: fetcher).fetcher).to be(fetcher)
    end

    it "builds and memoizes an AgentFetcher when none is injected" do
      fetcher = sync.fetcher

      expect(fetcher).to a_kind_of(Jira::AgentFetcher)
      expect(sync.fetcher).to be(fetcher)
    end
  end

  describe "#import" do
    it "creates nothing and reports blockers when blocked" do
      project.update_columns(jira_assignee: nil)

      result = sync.import([ { "key" => "UNS-1" } ])

      expect(result.blockers).to eq([ "assignee is not set" ])
      expect(result.created).to be_empty
      expect(project.workflows.count).to eq(0)
    end

    it "delegates to the importer with an empty result and returns it" do
      result = sync.import([ { "key" => "UNS-1" } ])

      expect(result.blockers).to be_empty
      expect(result.created).to eq([ "UNS-1" ])
      expect(project.workflows.pluck(:jira_ticket)).to eq([ "https://acme.atlassian.net/browse/UNS-1" ])
    end
  end
end
