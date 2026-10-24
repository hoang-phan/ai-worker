require "rails_helper"

RSpec.describe JiraSync, type: :model do
  let_personal_project("jira-sync-spec")

  describe "#label" do
    subject(:label) { described_class.new(jira_project: jira_project, parent_ticket: parent_ticket).label }

    let(:jira_project) { nil }
    let(:parent_ticket) { nil }

    context "with a Jira project only" do
      let(:jira_project) { "ABC" }

      it { is_expected.to eq("project ABC") }
    end

    context "with a parent ticket only" do
      let(:parent_ticket) { "ABC-12" }

      it { is_expected.to eq("parent ABC-12") }
    end

    context "with both" do
      let(:jira_project) { "ABC" }
      let(:parent_ticket) { "ABC-12" }

      it { is_expected.to eq("project ABC, parent ABC-12") }
    end

    context "with neither" do
      it { is_expected.to eq("all assigned tickets") }
    end

    context "with blank strings" do
      let(:jira_project) { "" }
      let(:parent_ticket) { "" }

      it { is_expected.to eq("all assigned tickets") }
    end
  end

  describe ".auto" do
    it "returns only syncs with auto_sync enabled" do
      auto = project.jira_syncs.create!(jira_project: "AUTO", auto_sync: true)
      manual = project.jira_syncs.create!(jira_project: "MANUAL", auto_sync: false)

      expect(described_class.auto).to include(auto)
      expect(described_class.auto).not_to include(manual)
    end
  end
end
