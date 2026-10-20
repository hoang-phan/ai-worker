require "rails_helper"

RSpec.describe Github::Writer do
  subject(:writer) { described_class.new(project) }

  let(:local_directory) { Dir.mktmpdir("github-writer-spec") }
  let(:project) { Project.new(name: "Github writer spec", kind: :personal, local_directory: local_directory, repo_full_name: "acme/widgets") }
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/42" }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "#request_review!" do
    it "posts reviewers[]= args to the PR's endpoint without -R" do
      allow(Open3).to receive(:capture3).and_return([ "{}", "", ok ])
      writer.request_review!(pr_url, %w[alice bob])

      expect(Open3).to have_received(:capture3).with(
        "gh", "api", "repos/acme/widgets/pulls/42/requested_reviewers",
        "-f", "reviewers[]=alice", "-f", "reviewers[]=bob",
        chdir: local_directory
      )
    end

    it "raises on an unparsable PR URL without calling gh" do
      allow(Open3).to receive(:capture3)

      expect { writer.request_review!("not a pr", [ "alice" ]) }.to raise_error(Github::CommandError, /could not parse PR number/)
      expect(Open3).not_to have_received(:capture3)
    end
  end

  describe "#enable_auto_merge!" do
    it "runs gh pr merge --auto --merge scoped to the repo" do
      allow(Open3).to receive(:capture3).and_return([ "", "", ok ])
      writer.enable_auto_merge!(pr_url)

      expect(Open3).to have_received(:capture3)
        .with("gh", "pr", "merge", pr_url, "--auto", "--merge", "-R", "acme/widgets", chdir: local_directory)
    end

    it "translates gh failures into CommandError" do
      allow(Open3).to receive(:capture3).and_return([ "", "auto-merge not allowed", failed ])

      expect { writer.enable_auto_merge!(pr_url) }.to raise_error(Github::CommandError, /gh pr merge .* failed: auto-merge not allowed/)
    end
  end

  describe "#checkout_pr!" do
    it "runs gh pr checkout scoped to the repo" do
      allow(Open3).to receive(:capture3).and_return([ "", "", ok ])
      writer.checkout_pr!(pr_url)

      expect(Open3).to have_received(:capture3)
        .with("gh", "pr", "checkout", pr_url, "-R", "acme/widgets", chdir: local_directory)
    end
  end
end
