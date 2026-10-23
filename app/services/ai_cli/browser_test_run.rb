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

    # Per kind: the label used in error messages, the directory under the root, the env-variable prefix, the Project
    # attributes holding the URL and login, and the extra env (key => name of a private reader) added to the credentials.
    # Adding a kind means adding one entry here.
    KIND_SETTINGS = {
      uat: {
        label: "UAT", dir_name: "uat_runs", env_prefix: "UAT",
        url_attr: :uat_url, username_attr: :uat_username, password_attr: :uat_password,
        extra_env: { "UAT_OUTPUT_DIR" => :output_dir_value, "JIRA_BASE_URL" => :jira_base_url_value }.freeze
      }.freeze,
      local: {
        label: "local", dir_name: "local_test_runs", env_prefix: "LOCAL",
        url_attr: :local_url, username_attr: :local_username, password_attr: :local_password,
        extra_env: { "LOCAL_URL" => :url, "LOCAL_OUTPUT_DIR" => :output_dir_value }.freeze
      }.freeze
    }.freeze

    KINDS = KIND_SETTINGS.keys.freeze

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
      KIND_SETTINGS.fetch(@kind)
    end

    def label
      settings[:label]
    end

    def dir_name
      settings[:dir_name]
    end

    def credential_env
      prefix = settings[:env_prefix]
      { "#{prefix}_USERNAME" => username, "#{prefix}_PASSWORD" => password }
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
      @project.public_send(settings[:url_attr])
    end

    def username
      @project.public_send(settings[:username_attr])
    end

    def password
      @project.public_send(settings[:password_attr])
    end
  end
end
