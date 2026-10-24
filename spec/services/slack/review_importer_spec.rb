require "rails_helper"

RSpec.describe Slack::ReviewImporter do
  let_tmpdir(:dir, "review-importer-spec")
  let(:project) do
    build_jira_project(local_directory: dir, slack_mention: "@reviewer")
  end
  let(:github) { instance_double(Github::Client, current_login: "me", pr_info: nil) }
  let(:importer) { described_class.new(project, github: github) }
  let(:result) { Slack::ReviewSync::Result.new(blockers: [], created: [], skipped: [], failed: [], skipped_reasons: Hash.new(0)) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/12" }
  let(:slack_url) { "https://acme.slack.com/archives/C0123456789/p1760000000123456" }
  let(:mention) { { "slack_url" => slack_url, "pr_urls" => [ pr_url ] } }

  after do
    project.destroy
  end

  def stub_pr(url, state: "OPEN", author: "someone")
    allow(github).to receive(:pr_info).with(url).and_return("state" => state, "author" => author)
  end

  it "returns the result it was given" do
    expect(importer.import([], result)).to equal(result)
  end

  it "creates a pr_review workflow for an open PR by someone else" do
    stub_pr(pr_url)

    importer.import([ mention ], result)

    expect(result.created).to eq([ pr_url ])
    workflow = project.workflows.pr_review.last
    expect([ workflow.slack_url, workflow.github_pr_url, workflow.status, workflow.position ]).to eq([ slack_url, pr_url, "implementing", 1 ])
  end

  it "ignores PRs from other repos" do
    other = "https://github.com/other/repo/pull/3"

    importer.import([ { "slack_url" => slack_url, "pr_urls" => [ other ] } ], result)

    expect(result.created).to be_empty
    expect(result.skipped).to be_empty
    expect(github).not_to have_received(:pr_info)
  end

  it "skips already-imported pairs without calling GitHub, but imports the same PR from another message" do
    build_pr_review_workflow(project, slack_url: slack_url, github_pr_url: pr_url, position: 1)
    stub_pr(pr_url)

    importer.import([ mention ], result)
    expect(result.skipped).to eq([ pr_url ])
    expect(result.skipped_reasons).to eq("already imported" => 1)
    expect(github).not_to have_received(:pr_info)

    importer.import([ { "slack_url" => "#{slack_url}9", "pr_urls" => [ pr_url ] } ], result)
    expect(result.created).to eq([ pr_url ])
  end

  it "dedupes the same pair repeated within one batch" do
    stub_pr(pr_url)

    importer.import([ mention, mention ], result)

    expect(result.created).to eq([ pr_url ])
    expect(result.skipped_reasons).to eq("already imported" => 1)
  end

  it "skips non-OPEN PRs with the state as the reason" do
    stub_pr(pr_url, state: "MERGED")

    importer.import([ mention ], result)

    expect(result.skipped).to eq([ pr_url ])
    expect(result.skipped_reasons).to eq("merged" => 1)
    expect(project.workflows.count).to eq(0)
  end

  it "skips the user's own PRs case-insensitively" do
    stub_pr(pr_url, author: "ME")

    importer.import([ mention ], result)

    expect(result.skipped_reasons).to eq("own PR" => 1)
  end

  it "looks up the current login once" do
    second = "https://github.com/acme/widgets/pull/13"
    stub_pr(pr_url)
    stub_pr(second)

    importer.import([ { "slack_url" => slack_url, "pr_urls" => [ pr_url, second ] } ], result)

    expect(github).to have_received(:current_login).once
  end

  it "records Github::CommandError in failed and carries on" do
    second = "https://github.com/acme/widgets/pull/13"
    allow(github).to receive(:pr_info).with(pr_url).and_raise(Github::CommandError, "gh exploded")
    stub_pr(second)

    importer.import([ { "slack_url" => slack_url, "pr_urls" => [ pr_url, second ] } ], result)

    expect(result.failed).to eq([ "#{pr_url}: gh exploded" ])
    expect(result.created).to eq([ second ])
  end

  it "records workflow validation errors in failed" do
    stub_pr(pr_url)
    invalid = instance_double(Workflow, save: false, errors: instance_double(ActiveModel::Errors, full_messages: [ "Bad", "Worse" ]))
    allow(project.workflows).to receive(:new).and_return(invalid)

    importer.import([ mention ], result)

    expect(result.failed).to eq([ "#{pr_url}: Bad and Worse" ])
    expect(result.created).to be_empty
  end
end
