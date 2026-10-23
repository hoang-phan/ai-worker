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
    it "is false on a clean tree and abort_merge! is a no-op" do
      expect(described_class.merge_in_progress?(project)).to be(false)
      expect { described_class.abort_merge!(project) }.not_to raise_error
    end

    it "detects an unfinished merge and aborts it" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "README.md", "branch change\n")
      commit_file(other, "README.md", "main change\n")
      git(other, "push", "origin", "main")
      described_class.update_with_main!(project, "feature/x")
      expect(described_class.merge_in_progress?(project)).to be(true)

      described_class.abort_merge!(project)

      expect(described_class.merge_in_progress?(project)).to be(false)
      expect(git(clone, "status", "--porcelain")).to be_empty
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
    def origin_sha(branch) = git(origin, "rev-parse", branch).strip

    it "returns :up_to_date and pushes nothing when HEAD equals origin/<branch>" do
      before_sha = origin_sha("main")

      expect(described_class.push_current!(project)).to eq(:up_to_date)
      expect(origin_sha("main")).to eq(before_sha)
    end

    it "pushes a local-only branch that is not on origin yet" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "work.txt", "wip\n")

      expect(described_class.push_current!(project)).to eq(:pushed)
      expect(origin_sha("feature/x")).to eq(git(clone, "rev-parse", "HEAD").strip)
    end

    it "pushes new commits when the branch is ahead of origin" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "one.txt", "one\n")
      git(clone, "push", "-u", "origin", "feature/x")
      commit_file(clone, "two.txt", "two\n")

      expect(described_class.push_current!(project)).to eq(:pushed)
      expect(origin_sha("feature/x")).to eq(git(clone, "rev-parse", "HEAD").strip)
      expect(git(origin, "ls-tree", "--name-only", "feature/x")).to include("two.txt")
    end

    it "rebases and pushes when origin moved and the first push is rejected" do
      commit_file(clone, "local.txt", "local\n")
      commit_file(other, "remote.txt", "remote\n")
      git(other, "push", "origin", "main")

      expect(described_class.push_current!(project)).to eq(:pushed)

      files = git(origin, "ls-tree", "--name-only", "main")
      expect(files).to include("local.txt").and include("remote.txt")
      expect(origin_sha("main")).to eq(git(clone, "rev-parse", "HEAD").strip)
    end

    it "raises Git::CommandError when the rebase conflicts" do
      commit_file(clone, "README.md", "local change\n")
      commit_file(other, "README.md", "remote change\n")
      git(other, "push", "origin", "main")
      remote_sha = origin_sha("main")

      expect { described_class.push_current!(project) }.to raise_error(Git::CommandError)
      expect(origin_sha("main")).to eq(remote_sha)
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
