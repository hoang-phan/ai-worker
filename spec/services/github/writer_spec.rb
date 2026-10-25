require "rails_helper"

RSpec.describe Github::Writer do
  subject(:writer) { described_class.new(project, runner: runner) }

  let(:project) { Project.new(name: "Github writer spec", kind: :personal, repo_full_name: "acme/widgets") }
  let(:runner) { instance_double(Github::Runner) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/42" }

  describe "#request_review!" do
    it "posts reviewers[]= args to the PR's endpoint without -R" do
      command = [
        "gh", "api", "repos/acme/widgets/pulls/42/requested_reviewers",
        "-f", "reviewers[]=alice", "-f", "reviewers[]=bob"
      ]
      allow(runner).to receive(:run!)

      writer.request_review!(pr_url, %w[alice bob])

      expect(runner).to have_received(:run!).with(command, scope_to_repo: false)
    end

    it "raises on an unparsable PR URL without calling the runner" do
      allow(runner).to receive(:run!)

      expect { writer.request_review!("not a pr", [ "alice" ]) }.to raise_error(Github::CommandError, /could not parse PR number/)
      expect(runner).not_to have_received(:run!)
    end
  end

  describe "#enable_auto_merge!" do
    it "runs gh pr merge --auto --merge scoped to the repo" do
      command = [ "gh", "pr", "merge", pr_url, "--auto", "--merge" ]
      allow(runner).to receive(:run!)

      writer.enable_auto_merge!(pr_url)

      expect(runner).to have_received(:run!).with(command)
    end

    it "propagates the runner's CommandError" do
      error = Github::CommandError.new("auto-merge not allowed")
      allow(runner).to receive(:run!).and_raise(error)

      expect { writer.enable_auto_merge!(pr_url) }.to raise_error(error)
    end
  end

  describe "#checkout_pr!" do
    it "runs gh pr checkout scoped to the repo" do
      command = [ "gh", "pr", "checkout", pr_url ]
      allow(runner).to receive(:run!)

      writer.checkout_pr!(pr_url)

      expect(runner).to have_received(:run!).with(command)
    end
  end
end
