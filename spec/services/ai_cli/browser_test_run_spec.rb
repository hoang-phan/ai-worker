require "rails_helper"
require "tmpdir"

RSpec.describe AiCli::BrowserTestRun do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:project) do
    Project.new(name: "Acme", uat_url: "https://uat.test", uat_username: "u", uat_password: "p",
                local_url: "http://localhost:3000", local_username: "lu", local_password: "lp",
                jira_base_url: "https://acme.atlassian.net")
  end
  let(:workflow) { Workflow.new.tap { |w| w.id = 42 } }

  after { FileUtils.remove_entry(root) }

  def run_for(kind) = described_class.new(project, workflow, kind: kind, root: root)

  describe "#validate!" do
    {
      uat: { url: :uat_url, user: :uat_username, pass: :uat_password, label: "UAT" },
      local: { url: :local_url, user: :local_username, pass: :local_password, label: "local" }
    }.each do |kind, f|
      it "requires a #{kind} URL" do
        project[f[:url]] = ""
        expect { run_for(kind).validate! }.to raise_error(ArgumentError, "project Acme has no #{f[:label]} URL")
      end

      %i[user pass].each do |field|
        it "requires a #{kind} #{field}" do
          project[f[field]] = nil
          expect { run_for(kind).validate! }
            .to raise_error(ArgumentError, "project Acme has no #{f[:label]} login (username/password)")
        end
      end

      it "passes with everything set for #{kind}" do
        expect { run_for(kind).validate! }.not_to raise_error
      end
    end

    it "rejects unknown kinds" do
      expect { run_for(:other) }.to raise_error(ArgumentError)
    end
  end

  describe "#output_dir" do
    it "is timestamped under the kind's runs directory" do
      expect(run_for(:uat).output_dir.to_s).to match(%r{\A#{root}/uat_runs/42/\d+\z})
      expect(run_for(:local).output_dir.to_s).to match(%r{\A#{root}/local_test_runs/42/\d+\z})
    end

    it "is stable for one run" do
      run = run_for(:uat)
      expect(run.output_dir).to equal(run.output_dir)
    end
  end

  describe "#env" do
    it "has the UAT keys" do
      run = run_for(:uat)
      expect(run.env).to eq("UAT_USERNAME" => "u", "UAT_PASSWORD" => "p", "UAT_OUTPUT_DIR" => run.output_dir.to_s,
                            "JIRA_BASE_URL" => "https://acme.atlassian.net")
    end

    it "has the local keys" do
      run = run_for(:local)
      expect(run.env).to eq("LOCAL_USERNAME" => "lu", "LOCAL_PASSWORD" => "lp", "LOCAL_URL" => "http://localhost:3000",
                            "LOCAL_OUTPUT_DIR" => run.output_dir.to_s)
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
