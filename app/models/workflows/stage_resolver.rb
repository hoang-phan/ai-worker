module Workflows
  # Pure lookup of which stage type is active for a (non-runbook) workflow, from its status, kind and project kind.
  class StageResolver
    # which stage type is currently active for each in-flight workflow status
    # (`merged` runs the post-merge Jira update; `done` and `jira_updated` are terminal-ish and
    # don't block the next workflow, nor does `merged`. `uat_waiting` / `uat_testing` / `uat_tested` come after the
    # ticket reached UAT: the agent tests it in a browser once the project's delay has passed.)
    STAGE_TYPE_BY_STATUS = { "implementing" => "implementation", "reviewing" => "pr_check", "merged" => "jira_update", "uat_testing" => "uat_test",
                             "local_testing" => "local_test", "ci_checking" => "ci_check", "ci_verifying" => "ci_verify",
                             "opening_pr" => "pr_create" }.freeze
    # `ci_loop` flow projects: implementation is its own stage that neither runs the checks nor opens the PR;
    # the PR stage and then the check/verify loop follow it (the check needs the pushed commit to post its result to).
    CI_LOOP_STAGE_TYPE_BY_STATUS = STAGE_TYPE_BY_STATUS.merge("implementing" => "simple_implementation").freeze
    # personal-project workflows have a single stage and skip "reviewing" entirely
    SIMPLE_STAGE_TYPE_BY_STATUS = { "implementing" => "task" }.freeze
    # PR-review workflows have a single stage, run once, and skip "reviewing"
    PR_REVIEW_STAGE_TYPE_BY_STATUS = { "implementing" => "pr_review" }.freeze

    # Not seeded with the workflow (older workflows predate them), so created the first time they're needed.
    LAZY_STAGE_TYPES = %w[jira_update uat_test local_test ci_check ci_verify pr_create simple_implementation].freeze

    def self.stage_type_for(status:, kind:, personal:, ci_loop: false)
      mapping = if kind.to_s == "pr_review" then PR_REVIEW_STAGE_TYPE_BY_STATUS
      elsif personal then SIMPLE_STAGE_TYPE_BY_STATUS
      elsif ci_loop then CI_LOOP_STAGE_TYPE_BY_STATUS
      else STAGE_TYPE_BY_STATUS
      end
      mapping[status.to_s]
    end
  end
end
