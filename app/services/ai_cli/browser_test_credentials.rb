module AiCli
  # Per-kind project credentials for browser-testing stages. Credentials only travel as environment variables of the
  # agent process, never in the prompt or the logs we write.
  class BrowserTestCredentials
    KIND_SETTINGS = {
      uat: {
        label: "UAT", env_prefix: "UAT",
        url_attr: :uat_url, username_attr: :uat_username, password_attr: :uat_password
      }.freeze,
      local: {
        label: "local", env_prefix: "LOCAL",
        url_attr: :local_url, username_attr: :local_username, password_attr: :local_password
      }.freeze
    }.freeze

    KINDS = KIND_SETTINGS.keys.freeze

    def initialize(project, kind:)
      raise ArgumentError, "unknown browser test kind #{kind.inspect}" unless KINDS.include?(kind)

      @project = project
      @kind = kind
    end

    def url
      @project.public_send(settings[:url_attr])
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

    def env
      prefix = settings[:env_prefix]
      { "#{prefix}_USERNAME" => username, "#{prefix}_PASSWORD" => password }
    end

    private

    def settings
      KIND_SETTINGS.fetch(@kind)
    end

    def label
      settings[:label]
    end

    def username
      @project.public_send(settings[:username_attr])
    end

    def password
      @project.public_send(settings[:password_attr])
    end
  end
end
