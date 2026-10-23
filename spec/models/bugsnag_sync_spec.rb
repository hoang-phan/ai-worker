require "rails_helper"

RSpec.describe BugsnagSync, type: :model do
  subject(:sync) { described_class.new(project: project, bugsnag_project: "web-app", jira_project: "WEB") }

  let_tmpdir(:local_directory, "bugsnag-sync-spec")
  let(:project) { build_personal_project(local_directory: local_directory) }

  it { is_expected.to be_valid }

  describe "presence validations" do
    %i[bugsnag_project jira_project].each do |attribute|
      it "requires #{attribute}" do
        sync[attribute] = ""

        expect(sync).not_to be_valid
        expect(sync.errors[attribute]).to include("can't be blank")
      end
    end
  end

  describe "numericality validations" do
    %i[min_events max_tickets].each do |attribute|
      it "accepts a positive integer for #{attribute}" do
        sync[attribute] = 1

        expect(sync).to be_valid
      end

      [ 0, -1, 1.5, nil ].each do |value|
        it "rejects #{value.inspect} for #{attribute}" do
          sync[attribute] = value

          expect(sync).not_to be_valid
          expect(sync.errors[attribute]).to be_present
        end
      end
    end
  end

  describe "#label" do
    it "joins the Bugsnag and Jira projects with an arrow" do
      expect(sync.label).to eq("web-app → WEB")
    end
  end

  describe ".auto" do
    it "returns only syncs with auto_sync enabled" do
      auto = described_class.create!(project: project, bugsnag_project: "auto-app", jira_project: "AUTO", auto_sync: true)
      manual = described_class.create!(project: project, bugsnag_project: "manual-app", jira_project: "MAN", auto_sync: false)

      expect(described_class.auto).to include(auto)
      expect(described_class.auto).not_to include(manual)
    end
  end
end
