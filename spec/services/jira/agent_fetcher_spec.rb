require "rails_helper"

RSpec.describe Jira::AgentFetcher do
  let(:run) { FakeDetachedRun.new }
  let(:fetcher) { described_class.new(jira_sync, root: Pathname("/tmp"), run: run) }
  let(:project) { double(jira_base_url: "https://acme.atlassian.net", jira_assignee: "me") }
  let(:jira_sync) { double(id: 1, project: project, jira_project: "UNS", parent_ticket: nil) }

  it "keeps only rows whose key matches KEY" do
    tmp = make_tmpdir("jira-fetcher-spec")
    runner = class_double(AiCli::Runner, poll: [ :completed, nil ])
    run = AiCli::DetachedRun.new(dir: Pathname(tmp).join("1"), result_name: "tickets.json", stale_after: described_class::STALE_AFTER,
                                 error_class: Jira::FetchError, runner: runner)
    fetcher = described_class.new(jira_sync, root: Pathname(tmp), run: run)
    FileUtils.mkdir_p(Pathname(tmp).join("1"))
    Pathname(tmp).join("1", "pid").write("1")
    Pathname(tmp).join("1", "tickets.json").write([
      { key: "UNS-1", summary: "ok" }, { key: "bad key", summary: "x" }, { key: "uns-2" }, "junk"
    ].to_json)

    expect(fetcher.poll).to eq([ { "key" => "UNS-1", "summary" => "ok" } ])
  end

  describe "#start" do
    it "runs in the sync dir with a prompt naming tickets.json and no allowed_tools" do
      tmp = make_tmpdir("jira-fetcher-spec")
      run.result_path = Pathname(tmp).join("1", "tickets.json")
      described_class.new(jira_sync, root: Pathname(tmp), run: run).start

      expect(run.started.keys).to contain_exactly(:cwd, :prompt)
      expect(run.started[:cwd]).to eq(Pathname(tmp).join("1"))
      expect(run.started[:prompt]).to include(Pathname(tmp).join("1", "tickets.json").to_s)
    end
  end

  describe "#poll" do
    it "passes rows through TicketRows" do
      run.rows = [ { "key" => "UNS-1", "summary" => "ok" }, { "key" => "bad key" }, "junk" ]

      expect(described_class.new(jira_sync, root: Pathname("/tmp"), run: run).poll).to eq([ { "key" => "UNS-1", "summary" => "ok" } ])
    end
  end

  it_behaves_like "a detached-run fetcher"
end
