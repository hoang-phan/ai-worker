require "rails_helper"

RSpec.describe Git::MergeState do
  include GitRepoHelper

  let_tmpdir(:root, "merge_state_spec")
  let(:fixture) { build_git_fixture(root) }
  let(:origin) { fixture[0] }
  let(:clone) { fixture[1] }
  let(:other) { build_other_clone(root, origin) }
  let(:project) { Project.new(name: "fixture", kind: :personal, local_directory: clone) }

  before do
    expect(clone).to start_with(File.realpath(Dir.tmpdir)).or start_with(Dir.tmpdir)
    clone
  end

  describe "#merge_in_progress? / #abort_merge!" do
    it "is false on a clean tree and abort_merge! is a no-op" do
      state = described_class.new(project)
      expect(state.merge_in_progress?).to be(false)
      expect { state.abort_merge! }.not_to raise_error
    end

    it "detects an unfinished merge and aborts it" do
      git(clone, "checkout", "-b", "feature/x")
      commit_file(clone, "README.md", "branch change\n")
      commit_file(other, "README.md", "main change\n")
      git(other, "push", "origin", "main")
      git(clone, "fetch", "origin", "main:main")
      state = described_class.new(project)
      expect(state.merge_main!).to eq(:conflict)
      expect(state.merge_in_progress?).to be(true)

      state.abort_merge!

      expect(state.merge_in_progress?).to be(false)
      expect(git(clone, "status", "--porcelain")).to be_empty
    end
  end
end
