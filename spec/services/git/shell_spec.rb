require "rails_helper"

RSpec.describe Git::Shell do
  include GitRepoHelper

  let_tmpdir(:root, "git_shell_spec")
  let(:fixture) { build_git_fixture(root) }
  let(:origin) { fixture[0] }
  let(:clone) { fixture[1] }
  let(:shell) { described_class.new(clone) }

  before do
    expect(clone).to start_with(File.realpath(Dir.tmpdir)).or start_with(Dir.tmpdir)
    clone
  end

  describe "#run" do
    it "returns stdout, stderr and status without raising" do
      out, _err, status = shell.run(%w[git rev-parse --abbrev-ref HEAD])
      expect(out.strip).to eq("main")
      expect(status).to be_success

      _out, err, status = shell.run(%w[git rev-parse --verify nope])
      expect(status).not_to be_success
      expect(err).not_to be_empty
    end
  end

  describe "#run!" do
    it "returns stdout on success" do
      expect(shell.run!(%w[git rev-parse --abbrev-ref HEAD]).strip).to eq("main")
    end

    it "raises CommandError with the command and stderr on failure" do
      expect { shell.run!(%w[git rev-parse --verify nope]) }
        .to raise_error(Git::CommandError, /\Agit rev-parse --verify nope failed: .+/)
    end
  end

  describe "#success?" do
    it "reflects the exit status" do
      expect(shell.success?(%w[git rev-parse --verify main])).to be(true)
      expect(shell.success?(%w[git rev-parse --verify nope])).to be(false)
    end
  end

  describe "#checkout!" do
    before do
      git(clone, "checkout", "-b", "feature")
      commit_file(clone, "shared.txt", "on feature\n")
      git(clone, "checkout", "main")
    end

    it "checks out when the tree is clean" do
      shell.checkout!(%w[git checkout feature])
      expect(git(clone, "rev-parse", "--abbrev-ref", "HEAD").strip).to eq("feature")
    end

    it "auto-stashes an untracked file that would be overwritten and retries" do
      File.write(File.join(clone, "shared.txt"), "local\n")

      shell.checkout!(%w[git checkout feature])

      expect(git(clone, "rev-parse", "--abbrev-ref", "HEAD").strip).to eq("feature")
      expect(File.read(File.join(clone, "shared.txt"))).to eq("on feature\n")
      expect(git(clone, "stash", "list")).to include("ai-worker: auto-stash before git checkout feature")
    end

    it "auto-stashes tracked modifications that would be overwritten" do
      git(clone, "checkout", "feature")
      commit_file(clone, "README.md", "feature readme\n")
      git(clone, "checkout", "main")
      File.write(File.join(clone, "README.md"), "dirty\n")

      shell.checkout!(%w[git checkout feature])

      expect(git(clone, "rev-parse", "--abbrev-ref", "HEAD").strip).to eq("feature")
      expect(git(clone, "stash", "list")).to include("auto-stash")
    end

    it "raises without stashing when the failure is not an overwrite" do
      File.write(File.join(clone, "dirty.txt"), "local\n")

      expect { shell.checkout!(%w[git checkout missing-branch]) }
        .to raise_error(Git::CommandError, /git checkout missing-branch failed/)
      expect(git(clone, "stash", "list")).to be_empty
      expect(File.exist?(File.join(clone, "dirty.txt"))).to be(true)
    end
  end
end
