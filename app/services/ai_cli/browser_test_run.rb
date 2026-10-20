require "fileutils"

module AiCli
  # Per-run setup shared by the browser-testing stages (uat_test, local_test): credential checks, the timestamped
  # output directory, the Playwright MCP config and the environment of credentials. Credentials only travel as
  # environment variables of the agent process, never in the prompt or the logs we write.
  class BrowserTestRun
    # The agent must not dispatch GitHub Actions itself (a project's UAT instructions can provide a guarded wrapper
    # script for test data instead). Denied for these stages only: other stages, e.g. runbooks, may legitimately use these.
    UAT_DISALLOWED_TOOLS = [ "Bash(gh workflow run:*)", "Bash(gh api:*)" ].freeze

    # Playwright MCP, pinned: headless, throwaway profile, `devtools` capability for the video/trace tools.
    PLAYWRIGHT_MCP_PACKAGE = "@playwright/mcp@0.0.83".freeze

    KINDS = %i[uat local].freeze

    def initialize(project, workflow, kind:, root: Rails.root.join("tmp"))
      raise ArgumentError, "unknown browser test kind #{kind.inspect}" unless KINDS.include?(kind)

      @project = project
      @workflow = workflow
      @kind = kind
      @root = Pathname(root)
    end

    def validate!
      if url.blank?
        raise ArgumentError, "project #{@project.name} has no #{label} URL"
      end
      if username.blank? || password.blank?
        raise ArgumentError, "project #{@project.name} has no #{label} login (username/password)"
      end

      self
    end

    # Not created until something needs it (mcp_config_path).
    def output_dir
      @output_dir ||= @root.join(dir_name, @workflow.id.to_s, Time.current.to_i.to_s)
    end

    # Writes the Playwright MCP config into the output dir and returns its path.
    def mcp_config_path
      FileUtils.mkdir_p(output_dir)
      path = output_dir.join("mcp.json")
      config = { mcpServers: { playwright: { command: "npx",
        args: [ "-y", PLAYWRIGHT_MCP_PACKAGE, "--headless", "--isolated", "--caps", "devtools", "--output-dir", output_dir.to_s ] } } }
      File.write(path, JSON.pretty_generate(config))
      path.to_s
    end

    def env
      case @kind
      when :uat
        { "UAT_USERNAME" => username, "UAT_PASSWORD" => password, "UAT_OUTPUT_DIR" => output_dir.to_s,
          "JIRA_BASE_URL" => @project.jira_base_url }
      when :local
        { "LOCAL_USERNAME" => username, "LOCAL_PASSWORD" => password, "LOCAL_URL" => url,
          "LOCAL_OUTPUT_DIR" => output_dir.to_s }
      end
    end

    def disallowed_tools
      UAT_DISALLOWED_TOOLS
    end

    private

    def label
      @kind == :uat ? "UAT" : "local"
    end

    def dir_name
      @kind == :uat ? "uat_runs" : "local_test_runs"
    end

    def url
      @project.public_send(:"#{@kind}_url")
    end

    def username
      @project.public_send(:"#{@kind}_username")
    end

    def password
      @project.public_send(:"#{@kind}_password")
    end
  end
end
