require "rails_helper"

RSpec.describe Jira::AgentFetcher do

  # Records the keyword args `start` receives and yields canned rows to `poll`.
  let(:fake_run_class) do
    Class.new do
      attr_reader :started
      attr_accessor :last_started_at, :rows, :result_path

      def start(**kwargs)
        @started = kwargs
      end

      def running?
        false
      end

      def poll
        yield rows
      end
    end
  end
  let(:run) { fake_run_class.new }
  let(:project) { double(jira_base_url: "https://acme.atlassian.net", jira_assignee: "me") }
  let(:jira_sync) { double(id: 1, project: project, jira_project: "UNS", parent_ticket: nil) }

  it "keeps only rows whose key matches KEY" do
    Dir.mktmpdir do |tmp|
      fetcher = described_class.new(jira_sync, root: Pathname(tmp))
      FileUtils.mkdir_p(Pathname(tmp).join("1"))
      Pathname(tmp).join("1", "pid").write("1")
      Pathname(tmp).join("1", "tickets.json").write([
        { key: "UNS-1", summary: "ok" }, { key: "bad key", summary: "x" }, { key: "uns-2" }, "junk"
      ].to_json)
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, nil ])

      expect(fetcher.poll).to eq([ { "key" => "UNS-1", "summary" => "ok" } ])
    end
  end

  describe "#start" do
    it "runs in the sync dir with a prompt naming tickets.json and no allowed_tools" do
      Dir.mktmpdir do |tmp|
        run.result_path = Pathname(tmp).join("1", "tickets.json")
        described_class.new(jira_sync, root: Pathname(tmp), run: run).start

        expect(run.started.keys).to contain_exactly(:cwd, :prompt)
        expect(run.started[:cwd]).to eq(Pathname(tmp).join("1"))
        expect(run.started[:prompt]).to include(Pathname(tmp).join("1", "tickets.json").to_s)
      end
    end
  end

  describe "#poll" do
    it "passes rows through TicketRows" do
      run.rows = [ { "key" => "UNS-1", "summary" => "ok" }, { "key" => "bad key" }, "junk" ]

      expect(described_class.new(jira_sync, root: Pathname("/tmp"), run: run).poll).to eq([ { "key" => "UNS-1", "summary" => "ok" } ])
    end
  end

  it "delegates running? and last_started_at to the run" do
    time = Time.utc(2026, 1, 1)
    run.last_started_at = time
    allow(run).to receive(:running?).and_return(true)
    fetcher = described_class.new(jira_sync, root: Pathname("/tmp"), run: run)

    expect(fetcher.running?).to be(true)
    expect(fetcher.last_started_at).to eq(time)
  end
end
