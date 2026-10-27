require "rails_helper"
require "tmpdir"

RSpec.describe AiCli::BrowserTestRun do
  let(:root) { Pathname(make_tmpdir("browser-test-run-spec")) }
  let(:project) do
    Project.new(name: "Acme", uat_url: "https://uat.test", uat_username: "u", uat_password: "p",
                local_url: "http://localhost:3000", local_username: "lu", local_password: "lp",
                jira_base_url: "https://acme.atlassian.net")
  end
  let(:workflow) { Workflow.new.tap { |w| w.id = 42 } }
  let(:clock) { -> { Time.zone.at(1_760_000_000) } }

  def run_for(kind) = described_class.new(project, workflow, kind: kind, root: root, clock: clock)

  describe "#validate!" do
    it "delegates to the credentials" do
      credentials = instance_double(AiCli::BrowserTestCredentials, validate!: nil)
      run = described_class.new(project, workflow, kind: :uat, root: root, credentials: credentials, clock: clock)

      expect(run.validate!).to equal(run)
      expect(credentials).to have_received(:validate!)
    end
  end

  describe "#output_dir" do
    it "is timestamped under the kind's runs directory" do
      expect(run_for(:uat).output_dir.to_s).to eq("#{root}/uat_runs/42/1760000000")
      expect(run_for(:local).output_dir.to_s).to eq("#{root}/local_test_runs/42/1760000000")
    end

    it "is stable for one run" do
      run = run_for(:uat)
      expect(run.output_dir).to equal(run.output_dir)
    end
  end

  describe "#env" do
    it "merges credentials with each kind's run environment" do
      credentials = instance_double(AiCli::BrowserTestCredentials, env: { "UAT_USERNAME" => "u", "UAT_PASSWORD" => "p" })
      run = described_class.new(project, workflow, kind: :uat, root: root, credentials: credentials, clock: clock)

      expect(run.env).to eq("UAT_USERNAME" => "u", "UAT_PASSWORD" => "p", "UAT_OUTPUT_DIR" => run.output_dir.to_s,
                            "JIRA_BASE_URL" => "https://acme.atlassian.net")

      local_credentials = instance_double(AiCli::BrowserTestCredentials, env: { "LOCAL_USERNAME" => "lu", "LOCAL_PASSWORD" => "lp" }, url: "http://localhost:3000")
      local_run = described_class.new(project, workflow, kind: :local, root: root, credentials: local_credentials, clock: clock)
      expect(local_run.env).to eq("LOCAL_USERNAME" => "lu", "LOCAL_PASSWORD" => "lp", "LOCAL_URL" => "http://localhost:3000",
                                  "LOCAL_OUTPUT_DIR" => local_run.output_dir.to_s)
    end
  end

  describe "#mcp_config" do
    it "returns the Playwright server config without touching the filesystem" do
      run = run_for(:uat)
      expect(run.mcp_config).to eq(
        mcpServers: { playwright: { command: "npx",
          args: [ "-y", "@playwright/mcp@0.0.83", "--headless", "--isolated", "--caps", "devtools",
                  "--output-dir", run.output_dir.to_s ] } }
      )
      expect(run.output_dir).not_to exist
    end

    it "does not include credentials" do
      expect(run_for(:local).mcp_config.to_s).not_to include("lp")
    end
  end

  describe "#mcp_config_path" do
    it "writes the Playwright MCP config into the output dir" do
      run = run_for(:uat)
      path = run.mcp_config_path
      expect(path).to eq(run.output_dir.join("mcp.json").to_s)

      server = JSON.parse(File.read(path)).dig("mcpServers", "playwright")
      expect(server["command"]).to eq("npx")
      expect(server["args"]).to eq([ "-y", "@playwright/mcp@0.0.83", "--headless", "--isolated", "--caps", "devtools",
                                     "--output-dir", run.output_dir.to_s ])
    end

    it "does not put credentials in the config" do
      content = File.read(run_for(:local).mcp_config_path)
      expect(content).not_to include("lp")
    end
  end

  describe "#disallowed_tools" do
    it "denies workflow dispatch and raw gh api" do
      expect(run_for(:uat).disallowed_tools).to eq([ "Bash(gh workflow run:*)", "Bash(gh api:*)" ])
    end
  end
end
