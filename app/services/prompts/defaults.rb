module Prompts
  # Built-in prompt bodies, used by Prompts::StagePrompt when a stage has no prompt of its own and no template.
  # Each body lives in defaults/<stage_type>.md and contains exactly the prompt; the description of what it is for
  # sits here. A new default is a new file plus an entry in DESCRIPTIONS.
  module Defaults
    # Stage type => when its default is used. The keys are the explicit list of stage types with a default.
    DESCRIPTIONS = {
      # Used by a `pr_review` stage when no template of that type exists yet, so Slack-driven reviews work without any
      # setup. Adapted from the global review-prs-from-slack skill, scoped to one PR.
      "pr_review" => "Slack-driven review of one PR",
      # Used by a `jira_update` stage when no template of that type exists, so the post-merge ticket update works
      # without any setup. {TESTER} is the project's configured Jira tester.
      "jira_update" => "Post-merge Jira ticket update",
      # Used by a `uat_test` stage when no template of that type exists. Runs once the ticket has sat in UAT for the
      # project's delay. Browser tools come from the Playwright MCP server the executor wires in for the run; the UAT
      # login, the output directory and the Jira credentials arrive as environment variables, never in the prompt.
      "uat_test" => "Browser test of a ticket on UAT",
      # Used by a `local_test` stage when no template of that type exists. Runs on the project's own development
      # server after implementation opened the PR and before it goes to review, with the same browser tooling as the
      # UAT test.
      "local_test" => "Browser test of a PR on the local development server",
      # Used by a `simple_implementation` stage (the ci_loop flow) when no template of that type exists. Unlike the
      # plain implementation prompt it neither runs the project's full checks nor opens the PR: the check, verify and
      # PR stages that follow do.
      "simple_implementation" => "Implementation without the full checks or the PR",
      # Used by a `ci_verify` stage when no template of that type exists. The `ci_check` stage ran the project's CI
      # command as plain code and saved its output; this run only reads it. {CI_OUTPUT} / {CI_STATUS} are that log
      # and exit status.
      "ci_verify" => "Reads the saved CI output and fixes what it reports",
      # Used by a `pr_create` stage when no template of that type exists. Runs once the check/verify loop passed (or,
      # for projects without the loop, right after implementation): the branch is committed locally and not pushed yet.
      "pr_create" => "Pushes the branch, opens the PR, updates the ticket"
    }.freeze

    DIRECTORY = File.expand_path("defaults", __dir__)

    def self.for(stage_type)
      bodies[stage_type.to_s]
    end

    def self.bodies
      @bodies ||= DESCRIPTIONS.keys.to_h do |type|
        [type, File.read(File.join(DIRECTORY, "#{type}.md")).freeze]
      end.freeze
    end
    private_class_method :bodies
  end
end
