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

  it "delegates find_pr_url to PrLocator" do
    allow(Open3).to receive(:capture3)

    expect(reader.find_pr_url(branch_name: "b", jira_ticket: "ENG-1", output: "opened #{pr_url}")).to eq(pr_url)
    expect(Open3).not_to have_received(:capture3)
  end

  describe "#review_decision" do
    def reviews(*pairs)
      { "latestReviews" => pairs.map { |login, state| { "author" => { "login" => login }, "state" => state } } }
    end

    it "returns CHANGES_REQUESTED when nobody approved" do
      stub_gh(reviews([ "alice", "CHANGES_REQUESTED" ], [ "bob", "COMMENTED" ]))

      expect(reader.review_decision(pr_url, %w[alice bob])).to eq("CHANGES_REQUESTED")
    end

    it "matches logins case-insensitively" do
      stub_gh(reviews([ "Alice", "APPROVED" ]))

      expect(reader.review_decision(pr_url, [ "ALICE" ])).to eq("APPROVED")
    end

    it "ignores reviews from users who are not assigned" do
      stub_gh(reviews([ "mallory", "APPROVED" ], [ "alice", "CHANGES_REQUESTED" ]))

      expect(reader.review_decision(pr_url, [ "alice" ])).to eq("CHANGES_REQUESTED")
    end

    it "considers every review when the reviewers list is empty" do
      stub_gh(reviews([ "anyone", "APPROVED" ]))

      expect(reader.review_decision(pr_url, [])).to eq("APPROVED")
    end

    it "returns nil when there are only comments or no reviews" do
      stub_gh(reviews([ "alice", "COMMENTED" ]))
      expect(reader.review_decision(pr_url, [ "alice" ])).to be_nil

      stub_gh("latestReviews" => nil)
      expect(reader.review_decision(pr_url, [ "alice" ])).to be_nil
    end
  end

  describe "#checks_failing?" do
    Github::FailingChecks::FAILED_CONCLUSIONS.each do |conclusion|
      it "is true for conclusion #{conclusion}" do
        stub_gh("statusCheckRollup" => [ { "conclusion" => "SUCCESS" }, { "conclusion" => conclusion.downcase } ])

        expect(reader).to be_checks_failing(pr_url)
      end
    end

    Github::FailingChecks::FAILED_STATES.each do |state|
      it "is true for state #{state}" do
        stub_gh("statusCheckRollup" => [ { "state" => state } ])

        expect(reader).to be_checks_failing(pr_url)
      end
    end

    it "ignores pending and successful checks" do
      stub_gh("statusCheckRollup" => [
        { "status" => "IN_PROGRESS", "conclusion" => "" },
        { "status" => "QUEUED", "conclusion" => nil },
        { "state" => "PENDING" },
        { "conclusion" => "SUCCESS" }
      ])

      expect(reader).not_to be_checks_failing(pr_url)
    end

    it "is false when there are no checks" do
      stub_gh("statusCheckRollup" => nil)

      expect(reader).not_to be_checks_failing(pr_url)
    end
  end

  describe "#workflow_run_state" do
    let(:since) { Time.zone.parse("2026-01-01T10:00:00Z") }

    def run(created_at, status:, conclusion: "", url: "https://github.com/acme/widgets/actions/runs/#{created_at}")
      { "createdAt" => created_at, "status" => status, "conclusion" => conclusion, "url" => url }
    end

    it "is :none when there are no runs since the cutoff" do
      stub_gh([ run("2026-01-01T09:59:59Z", status: "completed", conclusion: "success") ])

      expect(reader.workflow_run_state("ci.yml", since: since)).to eq(state: :none)
    end

    it "is :pending when the run has not completed" do
      stub_gh([ run("2026-01-01T10:05:00Z", status: "in_progress", url: "u1") ])

      expect(reader.workflow_run_state("ci.yml", since: since)).to eq(state: :pending, url: "u1")
    end

    it "is :failed with the conclusion otherwise" do
      stub_gh([ run("2026-01-01T10:05:00Z", status: "completed", conclusion: "cancelled", url: "u1") ])

      expect(reader.workflow_run_state("ci.yml", since: since)).to eq(state: :failed, url: "u1", conclusion: "cancelled")
    end

    it "picks the newest run" do
      stub_gh([
        run("2026-01-01T10:05:00Z", status: "completed", conclusion: "failure", url: "old"),
        run("2026-01-01T11:00:00Z", status: "completed", conclusion: "success", url: "new"),
        run("2026-01-01T10:30:00Z", status: "completed", conclusion: "failure", url: "mid")
      ])

      expect(reader.workflow_run_state("ci.yml", since: since)).to include(state: :success, url: "new")
    end

    it "uses the project's repo by default and a repo: override as -R" do
      stub_gh([])
      reader.workflow_run_state("ci.yml", since: since)
      reader.workflow_run_state("ci.yml", since: since, repo: "other/repo")

      expect(Open3).to have_received(:capture3).with(*%w[gh run list --workflow ci.yml], any_args, "-R", "acme/widgets", chdir: local_directory)
      expect(Open3).to have_received(:capture3).with(*%w[gh run list --workflow ci.yml], any_args, "-R", "other/repo", chdir: local_directory)
    end
  end

  describe "#pr_info" do
    it "tolerates missing fields" do
      stub_gh({})

      expect(reader.pr_info(pr_url)).to eq("state" => "", "author" => "", "head_ref" => "", "cross_repository" => false)
    end
  end

  it "never issues write commands" do
    stub_gh([])
    reader.workflow_run_state("ci.yml", since: Time.zone.now)

    expect(described_class.public_instance_methods(false)).not_to include(:request_review!, :enable_auto_merge!, :checkout_pr!)
  end
end
