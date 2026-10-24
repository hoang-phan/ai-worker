require "rails_helper"

RSpec.describe Git::Pusher do
  include GitRepoHelper

  let_tmpdir(:root, "pusher_spec")
  let(:fixture) { build_git_fixture(root) }
  let(:origin) { fixture[0] }
  let(:clone) { fixture[1] }
  let(:other) { build_other_clone(root, origin) }
  let(:project) { Project.new(name: "fixture", kind: :personal, local_directory: clone) }

  before do
    expect(clone).to start_with(File.realpath(Dir.tmpdir)).or start_with(Dir.tmpdir)
    clone
  end

  describe "#push_current!" do
    def origin_sha(branch) = git(origin, "rev-parse", branch).strip

    it "returns :up_to_date and pushes nothing when HEAD equals origin/<branch>" do
      before_sha = origin_sha("main")

      expect(described_class.new(project).push_current!).to eq(:up_to_date)
      expect(origin_sha("main")).to eq(before_sha)
    end

    it "pushes a local-only branch that is not on origin yet" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "work.txt", "wip\n")

      expect(described_class.new(project).push_current!).to eq(:pushed)
      expect(origin_sha("feature/x")).to eq(git(clone, "rev-parse", "HEAD").strip)
    end

    it "pushes new commits when the branch is ahead of origin" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "one.txt", "one\n")
      git(clone, "push", "-u", "origin", "feature/x")
      commit_file(clone, "two.txt", "two\n")

      expect(described_class.new(project).push_current!).to eq(:pushed)
      expect(origin_sha("feature/x")).to eq(git(clone, "rev-parse", "HEAD").strip)
      expect(git(origin, "ls-tree", "--name-only", "feature/x")).to include("two.txt")
    end

    it "rebases and pushes when origin moved and the first push is rejected" do
      commit_file(clone, "local.txt", "local\n")
      commit_file(other, "remote.txt", "remote\n")
      git(other, "push", "origin", "main")

      expect(described_class.new(project).push_current!).to eq(:pushed)

      files = git(origin, "ls-tree", "--name-only", "main")
      expect(files).to include("local.txt").and include("remote.txt")
      expect(origin_sha("main")).to eq(git(clone, "rev-parse", "HEAD").strip)
    end

    it "raises Git::CommandError when the rebase conflicts" do
      commit_file(clone, "README.md", "local change\n")
      commit_file(other, "README.md", "remote change\n")
      git(other, "push", "origin", "main")
      remote_sha = origin_sha("main")

      expect { described_class.new(project).push_current! }.to raise_error(Git::CommandError)
      expect(origin_sha("main")).to eq(remote_sha)
    end
  end
end
