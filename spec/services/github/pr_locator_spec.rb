require "rails_helper"

RSpec.describe Github::PrLocator do
  subject(:locator) { described_class.new(project, runner: runner) }

  let(:project) { Project.new(name: "Locator spec", kind: :personal, repo_full_name: "acme/widgets") }
  let(:runner) { instance_double(Github::Runner) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/42" }
  let(:view_args) { [ "gh", "pr", "view", "feat/x", "--json", "url" ] }
  let(:list_args) { [ "gh", "pr", "list", "--state", "open", "--limit", "100", "--json", "url,headRefName" ] }

  def locate(branch_name: "feat/x", jira_ticket: "ENG-1", output: nil)
    locator.call(branch_name: branch_name, jira_ticket: jira_ticket, output: output)
  end

  it "prefers the last PR URL in the output without calling gh" do
    allow(runner).to receive(:run!)
    output = "see #{pr_url} then https://github.com/acme/widgets/pull/43"

    expect(locate(output: output)).to eq("https://github.com/acme/widgets/pull/43")
    expect(runner).not_to have_received(:run!)
  end

  it "ignores PR URLs of other repos" do
    allow(runner).to receive(:run!).with(view_args).and_return(JSON.generate("url" => pr_url))

    expect(locate(output: "https://github.com/other/repo/pull/9")).to eq(pr_url)
  end

  it "matches the repo case-insensitively" do
    expect(locate(output: "https://github.com/Acme/Widgets/pull/7")).to eq("https://github.com/Acme/Widgets/pull/7")
  end

  it "falls back to the head branch" do
    allow(runner).to receive(:run!).with(view_args).and_return(JSON.generate("url" => pr_url))

    expect(locate).to eq(pr_url)
  end

  it "falls back to an open PR whose head branch contains the ticket key" do
    allow(runner).to receive(:run!).with(view_args).and_raise(Github::CommandError, "no PR")
    allow(runner).to receive(:run!).with(list_args).and_return(JSON.generate([
      { "url" => "https://github.com/acme/widgets/pull/1", "headRefName" => "feat/other" },
      { "url" => pr_url, "headRefName" => "bug/eng-1/slug" }
    ]))

    expect(locate).to eq(pr_url)
  end

  it "skips the head lookup for a blank branch" do
    allow(runner).to receive(:run!).with(list_args).and_return(JSON.generate([ { "url" => pr_url, "headRefName" => "ENG-1-x" } ]))

    expect(locate(branch_name: " ")).to eq(pr_url)
    expect(runner).not_to have_received(:run!).with(view_args)
  end

  it "skips the ticket lookup when there is no ticket key" do
    allow(runner).to receive(:run!).with(view_args).and_raise(Github::CommandError, "no PR")

    expect { locate(jira_ticket: "none") }.to raise_error(Github::CommandError, /no PR was found/)
    expect(runner).not_to have_received(:run!).with(list_args)
  end

  it "raises when nothing is found" do
    allow(runner).to receive(:run!).with(view_args).and_raise(Github::CommandError, "no PR")
    allow(runner).to receive(:run!).with(list_args).and_return("[]")

    expect { locate }.to raise_error(Github::CommandError, /no PR was found \(branch="feat\/x", ticket="ENG-1"\)/)
  end
end
