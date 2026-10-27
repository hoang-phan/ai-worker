require "fileutils"

module AiCli
  # Per-run setup shared by the browser-testing stages (uat_test, local_test): the timestamped output directory,
  # Playwright MCP config and environment plumbing.
  class BrowserTestRun
    # The agent must not dispatch GitHub Actions itself (a project's UAT instructions can provide a guarded wrapper
    # script for test data instead). Denied for these stages only: other stages, e.g. runbooks, may legitimately use these.
    UAT_DISALLOWED_TOOLS = [ "Bash(gh workflow run:*)", "Bash(gh api:*)" ].freeze

    # Playwright MCP, pinned: headless, throwaway profile, `devtools` capability for the video/trace tools.
    PLAYWRIGHT_MCP_PACKAGE = "@playwright/mcp@0.0.83".freeze

    # Per kind: the directory under the root and extra env (key => name of a private reader) added to the credentials.
    # Adding a kind means adding one entry here and one to BrowserTestCredentials.
    RUN_SETTINGS = {
      uat: {
        dir_name: "uat_runs",
        extra_env: { "UAT_OUTPUT_DIR" => :output_dir_value, "JIRA_BASE_URL" => :jira_base_url_value }.freeze
      }.freeze,
      local: {
        dir_name: "local_test_runs",
        extra_env: { "LOCAL_URL" => :url, "LOCAL_OUTPUT_DIR" => :output_dir_value }.freeze
      }.freeze
    }.freeze

    KIND_SETTINGS = BrowserTestCredentials::KIND_SETTINGS
    KINDS = BrowserTestCredentials::KINDS

    def initialize(project, workflow, kind:, root: Rails.root.join("tmp"), credentials: BrowserTestCredentials.new(project, kind: kind),
                   clock: -> { Time.current })
      @project = project
      @workflow = workflow
      @kind = kind
      @root = Pathname(root)
      @credentials = credentials
      @clock = clock
    end

    def validate!
      @credentials.validate!
      self
    end

    # Not created until something needs it (mcp_config_path).
    def output_dir
      @output_dir ||= @root.join(dir_name, @workflow.id.to_s, @clock.call.to_i.to_s)
    end

    # The Playwright MCP config for this run. Pure: touches neither the filesystem nor credentials.
    def mcp_config
      { mcpServers: { playwright: { command: "npx",
        args: [ "-y", PLAYWRIGHT_MCP_PACKAGE, "--headless", "--isolated", "--caps", "devtools", "--output-dir", output_dir.to_s ] } } }
    end

    # Writes the Playwright MCP config into the output dir and returns its path.
    def mcp_config_path
      FileUtils.mkdir_p(output_dir)
      path = output_dir.join("mcp.json")
      File.write(path, JSON.pretty_generate(mcp_config))
      path.to_s
    end

    def env
      credential_env.merge(extra_env)
    end

    def disallowed_tools
      UAT_DISALLOWED_TOOLS
    end

    private

    def settings
      RUN_SETTINGS.fetch(@kind)
    end

    def dir_name
      settings[:dir_name]
    end

    def credential_env
      @credentials.env
    end

    def extra_env
      settings[:extra_env].transform_values { |reader| send(reader) }
    end

    def output_dir_value
      output_dir.to_s
    end

    def jira_base_url_value
      @project.jira_base_url
    end

    def url
      @credentials.url
    end
  end
end
