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

  describe "local_directory validation" do
    context "with a separate clone" do
      it { is_expected.to be_valid }
    end

    context "when local_directory is blank" do
      let(:local_directory) { "" }

      it "is invalid" do
        expect(project).not_to be_valid
        expect(project.errors[:local_directory]).to include("can't be blank")
      end
    end

    context "when local_directory is the running app's live checkout" do
      let(:local_directory) { Rails.root.to_s }

      it "is invalid with a message pointing at a separate clone" do
        expect(project).not_to be_valid
        expect(project.errors[:local_directory].join).to include("live checkout")
      end
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

  describe "#slack_user_id_for" do
    it "delegates to Projects::SlackUserMap" do
      project = Project.new(slack_user_map: "octocat=U1")
      expect(project.slack_user_id_for("@Octocat")).to eq("U1")
    end
  end
end
