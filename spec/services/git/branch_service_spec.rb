require "rails_helper"

RSpec.describe Git::BranchService do
  include GitRepoHelper

  let_tmpdir(:root, "branch_service_spec")
  let(:fixture) { build_git_fixture(root) }
  let(:origin) { fixture[0] }
  let(:clone) { fixture[1] }
  let(:other) { build_other_clone(root, origin) }
  let(:project) { Project.new(name: "fixture", kind: :personal, local_directory: clone) }

  before do
    expect(clone).to start_with(File.realpath(Dir.tmpdir)).or start_with(Dir.tmpdir)
    clone
  end

  def current_branch = git(clone, "rev-parse", "--abbrev-ref", "HEAD").strip

  describe ".ensure_on_branch!" do
    it "puts the clone back on the workflow's branch when it was left elsewhere" do
      git(clone, "checkout", "-b", "feature/mine")
      git(clone, "checkout", "-b", "someone-elses-pr")

      described_class.ensure_on_branch!(project, "feature/mine")

      expect(current_branch).to eq("feature/mine")
    end

    it "does nothing when already on the branch" do
      git(clone, "checkout", "-b", "feature/mine")

      described_class.ensure_on_branch!(project, "feature/mine")

      expect(current_branch).to eq("feature/mine")
    end
  end

  describe ".create_branch!" do
    it "creates a new branch from an updated main" do
      commit_file(other, "new.txt", "from origin\n")
      git(other, "push", "origin", "main")

      described_class.create_branch!(project, "feature/x")

      expect(current_branch).to eq("feature/x")
      expect(File.exist?(File.join(clone, "new.txt"))).to be(true)
    end

    it "resumes an existing branch" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "work.txt", "wip\n")

      described_class.create_branch!(project, "feature/x")

      expect(current_branch).to eq("feature/x")
      expect(File.exist?(File.join(clone, "work.txt"))).to be(true)
    end
  end

  describe ".update_with_main!" do
    before do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "README.md", "branch change\n")
    end

    it "returns :merged on a clean merge" do
      commit_file(other, "other.txt", "other\n")
      git(other, "push", "origin", "main")

      expect(described_class.update_with_main!(project, "feature/x")).to eq(:merged)
      expect(File.exist?(File.join(clone, "other.txt"))).to be(true)
      expect(described_class.merge_in_progress?(project)).to be(false)
    end

    it "creates the branch from origin when it does not exist locally" do
      git(clone, "push", "origin", "feature/x")
      git(clone, "checkout", "main")
      git(clone, "branch", "-D", "feature/x")

      expect(described_class.update_with_main!(project, "feature/x")).to eq(:merged)
      expect(current_branch).to eq("feature/x")
      expect(File.read(File.join(clone, "README.md"))).to eq("branch change\n")
    end

    it "returns :conflict and leaves the merge in progress" do
      commit_file(other, "README.md", "main change\n")
      git(other, "push", "origin", "main")

      expect(described_class.update_with_main!(project, "feature/x")).to eq(:conflict)
      expect(File.exist?(File.join(clone, ".git", "MERGE_HEAD"))).to be(true)
      expect(described_class.merge_in_progress?(project)).to be(true)
    end
  end


  describe ".merge_in_progress? / .abort_merge!" do
    it "forwards to Git::MergeState" do
      expect(described_class.merge_in_progress?(project)).to be(false)
      expect { described_class.abort_merge!(project) }.not_to raise_error
    end
  end

  describe ".checkout_remote_branch!" do
    before do
      git(other, "checkout", "-b", "pr/1")
      commit_file(other, "pr.txt", "one\n")
      git(other, "push", "-u", "origin", "pr/1")
    end

    it "creates a tracking branch when none exists locally" do
      described_class.checkout_remote_branch!(project, "pr/1")

      expect(current_branch).to eq("pr/1")
      expect(git(clone, "rev-parse", "--abbrev-ref", "pr/1@{upstream}").strip).to eq("origin/pr/1")
    end

    it "fast-forwards an existing local branch" do
      described_class.checkout_remote_branch!(project, "pr/1")
      git(clone, "checkout", "main")
      commit_file(other, "pr2.txt", "two\n")
      git(other, "push", "origin", "pr/1")

      described_class.checkout_remote_branch!(project, "pr/1")

      expect(current_branch).to eq("pr/1")
      expect(File.exist?(File.join(clone, "pr2.txt"))).to be(true)
    end

    it "raises Git::CommandError when the branch has diverged" do
      described_class.checkout_remote_branch!(project, "pr/1")
      commit_file(clone, "local.txt", "local\n")
      commit_file(other, "remote.txt", "remote\n")
      git(other, "push", "origin", "pr/1")

      expect { described_class.checkout_remote_branch!(project, "pr/1") }
        .to raise_error(Git::CommandError)
    end
  end

  describe ".push_current!" do
    it "forwards to Git::Pusher" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "work.txt", "wip\n")

      expect(described_class.push_current!(project)).to eq(:pushed)
    end
  end

  describe "auto-stash on checkout" do
    it "stashes a dirty tree that blocks checkout and retries" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "README.md", "branch version\n")
      git(clone, "checkout", "main")
      File.write(File.join(clone, "README.md"), "dirty edit\n")

      described_class.create_branch!(project, "feature/x")

      expect(current_branch).to eq("feature/x")
      expect(git(clone, "stash", "list")).to include("ai-worker: auto-stash before git checkout feature/x")
    end
  end
end
