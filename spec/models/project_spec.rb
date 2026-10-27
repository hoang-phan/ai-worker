require "rails_helper"

RSpec.describe Project, type: :model do
  subject(:project) { described_class.new(name: "Spec project", kind: :personal, local_directory: local_directory) }

  let_tmpdir(:local_directory, "project-spec")

  describe "#runs_from_live_checkout?" do
    context "when local_directory is blank" do
      let(:local_directory) { "" }

      it { is_expected.not_to be_runs_from_live_checkout }
    end

    context "when local_directory is a separate clone" do
      it { is_expected.not_to be_runs_from_live_checkout }
    end

    context "when local_directory does not exist" do
      let(:local_directory) { File.join(Dir.tmpdir, "project-spec-missing-#{SecureRandom.hex(4)}") }

      it { is_expected.not_to be_runs_from_live_checkout }
    end

    context "when local_directory is the running app's root" do
      let(:local_directory) { Rails.root.to_s }

      it { is_expected.to be_runs_from_live_checkout }
    end

    context "when local_directory reaches the running app's root through a relative path" do
      let(:local_directory) { File.join(Rails.root, "app", "..") }

      it { is_expected.to be_runs_from_live_checkout }
    end

    context "when local_directory is a symlink to the running app's root" do
      let_tmpdir(:link_parent, "project-spec-link")
      let(:local_directory) { File.join(link_parent, "checkout") }

      before { File.symlink(Rails.root.to_s, local_directory) }

      it { is_expected.to be_runs_from_live_checkout }
    end
  end

  describe "validations" do
    it "delegates feature and format rules to Projects::Validator" do
      expect(project).to be_valid
      expect(described_class.validators).to include(an_instance_of(Projects::Validator))
    end
  end

  describe "#next_workflow_position" do
    before { project.save! }


    it "is 1 when the project has no workflows" do
      expect(project.next_workflow_position).to eq(1)
    end

    it "is one past the highest existing position" do
      build_task_workflow(project, position: 3)
      build_task_workflow(project, position: 7)

      expect(project.next_workflow_position).to eq(8)
    end
  end

  describe "jira site" do
    def stored_project(name, kind:, jira_base_url:)
      described_class.new(name: name, kind: kind, jira_base_url: jira_base_url, local_directory: local_directory)
                     .tap { |record| record.save!(validate: false) }
    end

    let!(:with_url) { stored_project("with-site-url", kind: :jira, jira_base_url: "https://site.atlassian.net") }
    let!(:nil_url) { stored_project("with-nil-url", kind: :jira, jira_base_url: nil) }
    let!(:blank_url) { stored_project("with-blank-url", kind: :jira, jira_base_url: "") }
    let!(:personal) { stored_project("personal-with-url", kind: :personal, jira_base_url: "https://site.atlassian.net") }

    describe ".with_jira_site" do
      it "includes Jira projects with a URL" do
        expect(described_class.with_jira_site).to include(with_url)
      end

      it "excludes Jira projects with a nil or blank URL and personal projects" do
        expect(described_class.with_jira_site).not_to include(nil_url, blank_url, personal)
      end
    end

    describe "#jira_site?" do
      it "is true only for a Jira project with a URL" do
        expect([ with_url, nil_url, blank_url, personal ].map(&:jira_site?)).to eq([ true, false, false, false ])
      end
    end
  end

  describe "#slack_user_id_for" do
    it "delegates to Projects::SlackUserMap" do
      project = Project.new(slack_user_map: "octocat=U1")
      expect(project.slack_user_id_for("@Octocat")).to eq("U1")
    end
  end

  describe "#add_agent_lessons" do
    before { project.save! }

    it "appends new lessons to the stored list" do
      project.update_column(:agent_lessons, "Use partial A")

      project.add_agent_lessons([ "Prefer services" ])

      expect(project.reload.agent_lessons).to eq("Use partial A\nPrefer services")
    end

    it "is a no-op for an empty list" do
      project.update_column(:agent_lessons, "Use partial A")

      expect { project.add_agent_lessons([]) }.not_to change { project.reload.agent_lessons }
    end

    it "uses Projects::AgentLessons merge rules" do
      project.update_column(:agent_lessons, "Use partial A")

      project.add_agent_lessons([ "use PARTIAL a", "Prefer services" ])

      expect(project.reload.agent_lessons).to eq("Use partial A\nPrefer services")
    end
  end
end
