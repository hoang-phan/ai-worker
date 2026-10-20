require "rails_helper"

RSpec.describe Github::Reader do
  subject(:reader) { described_class.new(project) }

  let(:local_directory) { Dir.mktmpdir("github-reader-spec") }
  let(:project) { Project.new(name: "Github reader spec", kind: :personal, local_directory: local_directory, repo_full_name: "acme/widgets") }
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/42" }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  def stub_gh(payload)
    out = payload.is_a?(String) ? payload : JSON.generate(payload)
    allow(Open3).to receive(:capture3).and_return([ out, "", ok ])
  end

  it "scopes commands to the repo and the project's directory" do
    stub_gh(state: "MERGED")

    expect(reader.merged?(pr_url)).to be(true)
    expect(Open3).to have_received(:capture3)
      .with("gh", "pr", "view", pr_url, "--json", "state", "-R", "acme/widgets", chdir: local_directory)
  end

  it "translates gh failures into CommandError" do
    allow(Open3).to receive(:capture3).and_return([ "", "no such PR", failed ])

    expect { reader.pr_title(pr_url) }.to raise_error(Github::CommandError, /no such PR/)
  end

  it "does not scope current_login to the repo" do
    stub_gh("octocat\n")

    expect(reader.current_login).to eq("octocat")
    expect(Open3).to have_received(:capture3).with("gh", "api", "user", "--jq", ".login", chdir: local_directory)
  end

  it "reads the PR title" do
    stub_gh("title" => "Fix it")

    expect(reader.pr_title(pr_url)).to eq("Fix it")
  end

  it "picks the approving review among assigned reviewers" do
    stub_gh("latestReviews" => [
      { "author" => { "login" => "Alice" }, "state" => "CHANGES_REQUESTED" },
      { "author" => { "login" => "bob" }, "state" => "APPROVED" }
    ])

    expect(reader.review_decision(pr_url, %w[alice bob])).to eq("APPROVED")
  end

  it "reports failing checks" do
    stub_gh("statusCheckRollup" => [ { "conclusion" => "failure" } ])

    expect(reader).to be_checks_failing(pr_url)
  end

  it "normalises pr_info" do
    stub_gh("state" => "open", "author" => { "login" => "octocat" }, "headRefName" => "feat/x", "isCrossRepository" => true)

    expect(reader.pr_info(pr_url)).to eq("state" => "OPEN", "author" => "octocat", "head_ref" => "feat/x", "cross_repository" => true)
  end

  it "reports the newest workflow run, honouring a repo override" do
    stub_gh([ { "createdAt" => "2026-01-01T11:00:00Z", "status" => "completed", "conclusion" => "success", "url" => "u" } ])

    result = reader.workflow_run_state("ci.yml", since: Time.zone.parse("2026-01-01T10:00:00Z"), repo: "other/repo")

    expect(result).to eq(state: :success, url: "u", conclusion: "success")
    expect(Open3).to have_received(:capture3).with(*%w[gh run list --workflow ci.yml], any_args, "-R", "other/repo", chdir: local_directory)
  end

  describe "#find_pr_url" do
    it "prefers the PR URL printed in the agent output without calling gh" do
      allow(Open3).to receive(:capture3)

      expect(reader.find_pr_url(branch_name: "b", jira_ticket: "ENG-1", output: "opened #{pr_url}")).to eq(pr_url)
      expect(Open3).not_to have_received(:capture3)
    end

    it "falls back to a PR whose head branch contains the ticket" do
      allow(Open3).to receive(:capture3) do |*args, **|
        args[0..2] == %w[gh pr view] ? [ "", "none", failed ] : [ JSON.generate([ { "url" => pr_url, "headRefName" => "bug/eng-1/x" } ]), "", ok ]
      end

      expect(reader.find_pr_url(branch_name: "b", jira_ticket: "ENG-1")).to eq(pr_url)
    end

    it "raises when nothing matches" do
      allow(Open3).to receive(:capture3).and_return([ "", "nope", failed ])

      expect { reader.find_pr_url(branch_name: "b", jira_ticket: "none") }.to raise_error(Github::CommandError, /no PR was found/)
    end
  end

  it "never issues write commands" do
    stub_gh([])
    reader.workflow_run_state("ci.yml", since: Time.zone.now)

    expect(described_class.public_instance_methods(false)).not_to include(:request_review!, :enable_auto_merge!, :checkout_pr!)
  end
end
