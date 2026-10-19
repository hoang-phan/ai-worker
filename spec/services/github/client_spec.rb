require "rails_helper"

RSpec.describe Github::Client do
  subject(:client) { described_class.new(project) }

  let(:local_directory) { Dir.mktmpdir("github-client-spec") }
  let(:project) { Project.new(name: "Github client spec", kind: :personal, local_directory: local_directory, repo_full_name: "acme/widgets") }
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/42" }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  def stub_gh(payload)
    out = payload.is_a?(String) ? payload : JSON.generate(payload)
    allow(Open3).to receive(:capture3).and_return([ out, "", ok ])
  end

  def stub_gh_failure(err = "boom")
    allow(Open3).to receive(:capture3).and_return([ "", err, failed ])
  end

  describe ".parse_reviewers" do
    it "splits on commas and whitespace, drops blanks and duplicates" do
      expect(described_class.parse_reviewers(" alice, bob  carol,,alice ,\n")).to eq(%w[alice bob carol])
    end

    it "returns an empty list for blank or nil input" do
      expect(described_class.parse_reviewers(nil)).to eq([])
      expect(described_class.parse_reviewers("  , ")).to eq([])
    end
  end

  describe "command execution" do
    it "appends -R <repo> and runs in the project's local_directory" do
      stub_gh(state: "MERGED")
      client.merged?(pr_url)

      expect(Open3).to have_received(:capture3)
        .with("gh", "pr", "view", pr_url, "--json", "state", "-R", "acme/widgets", chdir: local_directory)
    end

    it "does not append -R for unscoped commands" do
      stub_gh("octocat\n")

      expect(client.current_login).to eq("octocat")
      expect(Open3).to have_received(:capture3).with("gh", "api", "user", "--jq", ".login", chdir: local_directory)
    end

    it "raises CommandError with stderr when gh fails" do
      stub_gh_failure("no such PR")

      expect { client.merged?(pr_url) }.to raise_error(Github::CommandError, /no such PR/)
    end

    it "falls back to stdout in the error when stderr is empty" do
      allow(Open3).to receive(:capture3).and_return([ "stdout message", "", failed ])

      expect { client.merged?(pr_url) }.to raise_error(Github::CommandError, /stdout message/)
    end
  end

  describe "#review_decision" do
    def reviews(*pairs)
      { "latestReviews" => pairs.map { |login, state| { "author" => { "login" => login }, "state" => state } } }
    end

    it "lets an approval from any wanted reviewer win over CHANGES_REQUESTED" do
      stub_gh(reviews([ "alice", "CHANGES_REQUESTED" ], [ "bob", "APPROVED" ]))

      expect(client.review_decision(pr_url, %w[alice bob])).to eq("APPROVED")
    end

    it "returns CHANGES_REQUESTED when nobody approved" do
      stub_gh(reviews([ "alice", "CHANGES_REQUESTED" ], [ "bob", "COMMENTED" ]))

      expect(client.review_decision(pr_url, %w[alice bob])).to eq("CHANGES_REQUESTED")
    end

    it "matches logins case-insensitively" do
      stub_gh(reviews([ "Alice", "APPROVED" ]))

      expect(client.review_decision(pr_url, [ "ALICE" ])).to eq("APPROVED")
    end

    it "ignores reviews from users who are not assigned" do
      stub_gh(reviews([ "mallory", "APPROVED" ], [ "alice", "CHANGES_REQUESTED" ]))

      expect(client.review_decision(pr_url, [ "alice" ])).to eq("CHANGES_REQUESTED")
    end

    it "considers every review when the reviewers list is empty" do
      stub_gh(reviews([ "anyone", "APPROVED" ]))

      expect(client.review_decision(pr_url, [])).to eq("APPROVED")
    end

    it "returns nil when there are only comments or no reviews" do
      stub_gh(reviews([ "alice", "COMMENTED" ]))
      expect(client.review_decision(pr_url, [ "alice" ])).to be_nil

      stub_gh("latestReviews" => nil)
      expect(client.review_decision(pr_url, [ "alice" ])).to be_nil
    end
  end

  describe "#checks_failing?" do
    Github::Client::FAILED_CONCLUSIONS.each do |conclusion|
      it "is true for conclusion #{conclusion}" do
        stub_gh("statusCheckRollup" => [ { "conclusion" => "SUCCESS" }, { "conclusion" => conclusion.downcase } ])

        expect(client).to be_checks_failing(pr_url)
      end
    end

    Github::Client::FAILED_STATES.each do |state|
      it "is true for state #{state}" do
        stub_gh("statusCheckRollup" => [ { "state" => state } ])

        expect(client).to be_checks_failing(pr_url)
      end
    end

    it "ignores pending and successful checks" do
      stub_gh("statusCheckRollup" => [
        { "status" => "IN_PROGRESS", "conclusion" => "" },
        { "status" => "QUEUED", "conclusion" => nil },
        { "state" => "PENDING" },
        { "conclusion" => "SUCCESS" }
      ])

      expect(client).not_to be_checks_failing(pr_url)
    end

    it "is false when there are no checks" do
      stub_gh("statusCheckRollup" => nil)

      expect(client).not_to be_checks_failing(pr_url)
    end
  end

  describe "#workflow_run_state" do
    let(:since) { Time.zone.parse("2026-01-01T10:00:00Z") }

    def run(created_at, status:, conclusion: "", url: "https://github.com/acme/widgets/actions/runs/#{created_at}")
      { "createdAt" => created_at, "status" => status, "conclusion" => conclusion, "url" => url }
    end

    it "is :none when there are no runs since the cutoff" do
      stub_gh([ run("2026-01-01T09:59:59Z", status: "completed", conclusion: "success") ])

      expect(client.workflow_run_state("ci.yml", since: since)).to eq(state: :none)
    end

    it "is :pending when the run has not completed" do
      stub_gh([ run("2026-01-01T10:05:00Z", status: "in_progress", url: "u1") ])

      expect(client.workflow_run_state("ci.yml", since: since)).to eq(state: :pending, url: "u1")
    end

    it "is :success for a successful completed run" do
      stub_gh([ run("2026-01-01T10:05:00Z", status: "completed", conclusion: "success", url: "u1") ])

      expect(client.workflow_run_state("ci.yml", since: since)).to eq(state: :success, url: "u1", conclusion: "success")
    end

    it "is :failed with the conclusion otherwise" do
      stub_gh([ run("2026-01-01T10:05:00Z", status: "completed", conclusion: "cancelled", url: "u1") ])

      expect(client.workflow_run_state("ci.yml", since: since)).to eq(state: :failed, url: "u1", conclusion: "cancelled")
    end

    it "picks the newest run" do
      stub_gh([
        run("2026-01-01T10:05:00Z", status: "completed", conclusion: "failure", url: "old"),
        run("2026-01-01T11:00:00Z", status: "completed", conclusion: "success", url: "new"),
        run("2026-01-01T10:30:00Z", status: "completed", conclusion: "failure", url: "mid")
      ])

      expect(client.workflow_run_state("ci.yml", since: since)).to include(state: :success, url: "new")
    end

    it "uses the project's repo by default and a repo: override as -R" do
      stub_gh([])
      client.workflow_run_state("ci.yml", since: since)
      client.workflow_run_state("ci.yml", since: since, repo: "other/repo")

      expect(Open3).to have_received(:capture3).with(*%w[gh run list --workflow ci.yml], any_args, "-R", "acme/widgets", chdir: local_directory)
      expect(Open3).to have_received(:capture3).with(*%w[gh run list --workflow ci.yml], any_args, "-R", "other/repo", chdir: local_directory)
    end
  end

  describe "#find_pr_url" do
    let(:other_url) { "https://github.com/someone/else/pull/7" }

    it "prefers the last PR URL for this repo in the agent output" do
      allow(Open3).to receive(:capture3)

      output = "see #{other_url} and #{pr_url} then https://github.com/Acme/Widgets/pull/43"
      result = client.find_pr_url(branch_name: "feature", jira_ticket: "ENG-1", output: output)

      expect(result).to eq("https://github.com/Acme/Widgets/pull/43")
      expect(Open3).not_to have_received(:capture3)
    end

    it "ignores URLs from other repos and falls back to the head branch" do
      stub_gh("url" => pr_url)

      result = client.find_pr_url(branch_name: "feature", jira_ticket: "ENG-1", output: other_url)

      expect(result).to eq(pr_url)
      expect(Open3).to have_received(:capture3).with("gh", "pr", "view", "feature", "--json", "url", "-R", "acme/widgets", chdir: local_directory)
    end

    it "falls back to an open PR whose head branch contains the ticket key" do
      allow(Open3).to receive(:capture3) do |*args, **|
        if args[0..2] == %w[gh pr view]
          [ "", "no pull requests found", failed ]
        else
          [ JSON.generate([
            { "url" => "https://github.com/acme/widgets/pull/1", "headRefName" => "feature/other" },
            { "url" => pr_url, "headRefName" => "bug/eng-1/fix-thing" }
          ]), "", ok ]
        end
      end

      expect(client.find_pr_url(branch_name: "feature", jira_ticket: "Fix ENG-1 please")).to eq(pr_url)
    end

    it "skips the head lookup for a blank branch" do
      stub_gh([ { "url" => pr_url, "headRefName" => "ENG-1-x" } ])

      expect(client.find_pr_url(branch_name: "", jira_ticket: "ENG-1")).to eq(pr_url)
      expect(Open3).to have_received(:capture3).once
    end

    it "raises CommandError when nothing matches" do
      allow(Open3).to receive(:capture3) do |*args, **|
        args[0..2] == %w[gh pr view] ? [ "", "nope", failed ] : [ "[]", "", ok ]
      end

      expect { client.find_pr_url(branch_name: "feature", jira_ticket: "ENG-1") }
        .to raise_error(Github::CommandError, /no PR was found/)
    end

    it "raises when the ticket has no recognisable key and earlier lookups fail" do
      stub_gh_failure

      expect { client.find_pr_url(branch_name: "feature", jira_ticket: "nothing") }
        .to raise_error(Github::CommandError)
    end
  end

  describe "#pr_info" do
    it "normalises the gh payload" do
      stub_gh("state" => "open", "author" => { "login" => "octocat" }, "headRefName" => "feat/x", "isCrossRepository" => true)

      expect(client.pr_info(pr_url)).to eq(
        "state" => "OPEN", "author" => "octocat", "head_ref" => "feat/x", "cross_repository" => true
      )
    end

    it "tolerates missing fields" do
      stub_gh({})

      expect(client.pr_info(pr_url)).to eq("state" => "", "author" => "", "head_ref" => "", "cross_repository" => false)
    end
  end

  describe "#request_review!" do
    it "posts reviewers[]= args to the PR's endpoint without -R" do
      stub_gh("{}")
      client.request_review!(pr_url, %w[alice bob])

      expect(Open3).to have_received(:capture3).with(
        "gh", "api", "repos/acme/widgets/pulls/42/requested_reviewers",
        "-f", "reviewers[]=alice", "-f", "reviewers[]=bob",
        chdir: local_directory
      )
    end

    it "raises on an unparsable PR URL without calling gh" do
      allow(Open3).to receive(:capture3)

      expect { client.request_review!("not a pr", [ "alice" ]) }.to raise_error(Github::CommandError, /could not parse PR number/)
      expect(Open3).not_to have_received(:capture3)
    end
  end
end
