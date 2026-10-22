require "rails_helper"

RSpec.describe Bugsnag::Triager do

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
  let(:project) { double(local_directory: "/work/app", repo_full_name: "acme/app", jira_base_url: "https://acme.atlassian.net") }
  let(:sync) do
    double(id: 1, project: project, bugsnag_project: "bp", last_synced_at: nil, min_events: 1, max_tickets: 3,
           jira_project: "UNS", ledger: {})
  end
  it "needs a valid bugsnag id and jira key" do
    Dir.mktmpdir do |tmp|
      triager = described_class.new(sync, root: Pathname(tmp))
      FileUtils.mkdir_p(Pathname(tmp).join("1"))
      Pathname(tmp).join("1", "pid").write("1")
      Pathname(tmp).join("1", "result.json").write([
        { bugsnag_id: "abc123def456", jira_key: "UNS-12" },
        { bugsnag_id: "short", jira_key: "UNS-13" },
        { bugsnag_id: "abc123def456", jira_key: "bad" },
        "junk"
      ].to_json)
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, nil ])

      expect(triager.poll).to eq([ { "bugsnag_id" => "abc123def456", "jira_key" => "UNS-12" } ])
    end
  end

  describe "#start" do
    it "runs in the project's local directory with ALLOWED_TOOLS and a prompt naming result.json" do
      root = Pathname("/tmp/bugsnag-root")
      run.result_path = root.join("1", "result.json")
      described_class.new(sync, root: root, run: run).start

      expect(run.started[:cwd]).to eq("/work/app")
      expect(run.started[:allowed_tools]).to eq(described_class::ALLOWED_TOOLS)
      expect(run.started[:prompt]).to include(root.join("1", "result.json").to_s)
    end
  end

  describe "#poll" do
    it "passes rows through TriageRows" do
      run.rows = [ { "bugsnag_id" => "abc123def456", "jira_key" => "UNS-12" }, { "bugsnag_id" => "short", "jira_key" => "UNS-13" }, "junk" ]

      expect(described_class.new(sync, root: Pathname("/tmp"), run: run).poll).to eq([ { "bugsnag_id" => "abc123def456", "jira_key" => "UNS-12" } ])
    end
  end

  it "delegates running? and last_started_at to the run" do
    time = Time.utc(2026, 1, 1)
    run.last_started_at = time
    allow(run).to receive(:running?).and_return(true)
    triager = described_class.new(sync, root: Pathname("/tmp"), run: run)

    expect(triager.running?).to be(true)
    expect(triager.last_started_at).to eq(time)
  end

  describe ".summary" do
    it "lists the newly added keys" do
      expect(described_class.summary(%w[UNS-1 UNS-2])).to eq("2 new ticket(s): UNS-1, UNS-2")
    end

    it "says nothing new when no keys were added" do
      expect(described_class.summary([])).to eq("nothing new")
    end
  end
end
