require "json"

module Github
  # Finds the PR the implementation run opened. The agent may push to a branch
  # named differently from `workflow.branch_name` (e.g. `bug/ENG-1/slug` per
  # the target repo's conventions), so try, in order: the PR URL the agent
  # printed, the workflow's own branch name, then any open PR whose head
  # branch contains the Jira ticket. Read-only.
  class PrLocator
    TICKET_KEY = /[A-Z][A-Z0-9]+-\d+/i

    def initialize(project, runner: Runner.new(project))
      @project = project
      @runner = runner
    end

    def call(branch_name:, jira_ticket:, output: nil)
      url_from_output(output) ||
        url_for_head(branch_name) ||
        url_for_ticket(jira_ticket) ||
        raise(CommandError, "agent finished but no PR was found (branch=#{branch_name.inspect}, ticket=#{jira_ticket.inspect})")
    end

    private

    attr_reader :project, :runner

    # Last PR URL for this project's repo printed in the agent's output.
    def url_from_output(output)
      pattern = %r{https://github\.com/#{Regexp.escape(project.repo_full_name)}/pull/\d+}i
      output.to_s.scan(pattern).last
    end

    def url_for_head(branch_name)
      return if branch_name.blank?

      JSON.parse(runner.run!([ "gh", "pr", "view", branch_name, "--json", "url" ]))["url"]
    rescue CommandError
      nil
    end

    def url_for_ticket(jira_ticket)
      key = jira_ticket.to_s[TICKET_KEY]
      return unless key

      out = runner.run!([ "gh", "pr", "list", "--state", "open", "--limit", "100", "--json", "url,headRefName" ])
      prs = JSON.parse(out).select { |pr| pr["headRefName"].to_s.downcase.include?(key.downcase) }
      prs.first&.dig("url")
    end
  end
end
