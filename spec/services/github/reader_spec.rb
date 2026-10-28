require "rails_helper"

RSpec.describe Github::Reader do
  subject(:reader) { described_class.new(project, runner: runner) }

  let(:project) { Project.new(name: "Github reader spec", kind: :personal, repo_full_name: "acme/widgets") }
  let(:runner) { instance_double(Github::Runner) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/42" }

  def stub_run(command, result, **options)
    allow(runner).to receive(:run!).with(command, **options).and_return(result)
  end

  it "looks up a branch PR URL with the url field" do
    command = [ "gh", "pr", "view", "feat/x", "--json", "url" ]
    stub_run(command, JSON.generate("url" => pr_url))

    expect(reader.pr_url_for_branch("feat/x")).to eq(pr_url)
    expect(runner).to have_received(:run!).with(command)
  end

  it "normalises PR info from the requested fields" do
    command = [ "gh", "pr", "view", pr_url, "--json", "state,author,headRefName,isCrossRepository" ]
    stub_run(command, JSON.generate(
      "state" => "open", "author" => { "login" => "octocat" }, "headRefName" => "feat/x", "isCrossRepository" => true
    ))

    expect(reader.pr_info(pr_url)).to eq(
      "state" => "OPEN", "author" => "octocat", "head_ref" => "feat/x", "cross_repository" => true
    )
  end

  it "normalises missing PR info fields" do
    command = [ "gh", "pr", "view", pr_url, "--json", "state,author,headRefName,isCrossRepository" ]
    stub_run(command, "{}")

    expect(reader.pr_info(pr_url)).to eq(
      "state" => "", "author" => "", "head_ref" => "", "cross_repository" => false
    )
  end

  it "reads the PR title with the title field" do
    command = [ "gh", "pr", "view", pr_url, "--json", "title" ]
    stub_run(command, JSON.generate("title" => "Fix it"))

    expect(reader.pr_title(pr_url)).to eq("Fix it")
  end

  it "reads the authenticated login without repository scoping" do
    command = [ "gh", "api", "user", "--jq", ".login" ]
    stub_run(command, "octocat\n", scope_to_repo: false)

    expect(reader.current_login).to eq("octocat")
    expect(runner).to have_received(:run!).with(command, scope_to_repo: false)
  end

  it "reads whether a PR is merged with the state field" do
    command = [ "gh", "pr", "view", pr_url, "--json", "state" ]
    stub_run(command, JSON.generate("state" => "MERGED"))

    expect(reader.merged?(pr_url)).to be(true)
  end

  it "derives the review decision from latest reviews JSON" do
    command = [ "gh", "pr", "view", pr_url, "--json", "latestReviews" ]
    reviews = [ { "author" => { "login" => "alice" }, "state" => "APPROVED" } ]
    stub_run(command, JSON.generate("latestReviews" => reviews))

    expect(reader.review_decision(pr_url, [ "alice" ])).to eq("APPROVED")
  end

  it "detects failing checks from the status check rollup JSON" do
    command = [ "gh", "pr", "view", pr_url, "--json", "statusCheckRollup" ]
    rollup = [ { "conclusion" => "FAILURE" } ]
    stub_run(command, JSON.generate("statusCheckRollup" => rollup))

    expect(reader).to be_checks_failing(pr_url)
  end

  it "returns the state for the parsed workflow runs" do
    workflow = "ci.yml"
    since = Time.zone.parse("2026-01-01T10:00:00Z")
    command = [ "gh", "run", "list", "--workflow", workflow, "--limit", "20", "--json", "status,conclusion,createdAt,url" ]
    runs = [ { "createdAt" => "2026-01-01T11:00:00Z", "status" => "completed", "conclusion" => "success", "url" => "u" } ]
    stub_run(command, JSON.generate(runs), repo: "acme/widgets")

    expect(reader.workflow_run_state(workflow, since: since)).to eq(state: :success, url: "u", conclusion: "success")
  end

  it "uses a repo override for workflow runs" do
    workflow = "ci.yml"
    command = [ "gh", "run", "list", "--workflow", workflow, "--limit", "20", "--json", "status,conclusion,createdAt,url" ]
    stub_run(command, "[]", repo: "other/repo")
    expect(reader.workflow_run_state(workflow, since: Time.zone.now, repo: "other/repo")).to eq(state: :none)

    expect(runner).to have_received(:run!).with(command, repo: "other/repo")
  end

  it "delegates PR location to PrLocator with its runner" do
    allow(runner).to receive(:run!)

    expect(reader.find_pr_url(branch_name: "feat/x", jira_ticket: "ENG-1", output: "opened #{pr_url}")).to eq(pr_url)
    expect(runner).not_to have_received(:run!)
  end

  it "uses its runner when PrLocator falls back to the branch" do
    command = [ "gh", "pr", "view", "feat/x", "--json", "url" ]
    stub_run(command, JSON.generate("url" => pr_url))

    expect(reader.find_pr_url(branch_name: "feat/x", jira_ticket: "ENG-1", output: "no PR URL")).to eq(pr_url)
    expect(runner).to have_received(:run!).with(command)
  end
end
