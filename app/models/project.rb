class Project < ApplicationRecord
  has_many :workflows, dependent: :destroy
  has_many :jira_syncs, dependent: :destroy
  has_many :bugsnag_syncs, dependent: :destroy

  # How a Jira project's development workflows run. standard: implementation (checks and PR included) then review.
  # ci_loop: implementation without checks or PR, then the PR stage (push, open PR), then a check/verify loop on the
  # project's `ci_command` against the pushed commit, then review. A flow, not a kind: a ci_loop project is still a Jira project in every other respect.
  enum :flow, { standard: 0, ci_loop: 1 }, prefix: :flow

  # jira: GitHub-backed projects driven by Jira tickets; they go through
  # branch/PR/review stages, and can optionally pull workflows from Jira.
  # personal: local-only projects where each workflow is a single task
  # description that gets implemented and committed directly, no PR involved.
  # Runbook (deploy/release) runs are not a project kind: any project can have any
  # number of `Workflow#kind = runbook` workflows, each with its own stages.
  enum :kind, { jira: 0, personal: 1 }

  # Jira projects that have a site URL; the only ones the Jira sync and hours sync act on.
  scope :with_jira_site, -> { jira.where.not(jira_base_url: [ nil, "" ]) }

  # UAT login the agent types into the browser during the post-UAT test; stored encrypted.
  encrypts :uat_password
  # Login for the local (development server) test that runs before review; stored encrypted too.
  encrypts :local_password

  validates :name, presence: true
  validates_with Projects::Validator

  # True when `local_directory` is the checkout this app is running from. Agents
  # branch/pull/merge and may migrate in the project's clone, which would swap
  # the live code and hit the live dev DB — self-evolving needs its own clone.
  def runs_from_live_checkout?
    Projects::LiveCheckout.new(local_directory).live?
  end

  # Position for a workflow appended after the project's existing ones.
  def next_workflow_position
    (workflows.maximum(:position) || 0) + 1
  end

  # Jira projects on the ci_loop flow run simple_implementation -> pr_create -> (ci_check -> ci_verify)* before review
  # (see docs/RUNBOOK.md).
  def ci_loop_ready?
    jira? && flow_ci_loop?
  end

  # Instance form of the `with_jira_site` scope.
  def jira_site? = jira? && jira_base_url.present?

  def local_test_ready?
    jira? && local_test_enabled? && local_url.present?
  end

  # `slack_user_map` is one `github-login=SlackUserID` per line (commas work too), used to tag reviewers in Slack.
  def slack_user_id_for(github_login)
    Projects::SlackUserMap.new(slack_user_map).slack_id_for(github_login)
  end

  def skill_catalog = Projects::SkillCatalog.new(local_directory)

  # Append distilled review lessons to `agent_lessons` via Projects::AgentLessons
  # (case-insensitive de-dup, newest MAX lines). Skips validations/callbacks.
  def add_agent_lessons(lessons)
    return if Array(lessons).empty?

    update_column(:agent_lessons, Projects::AgentLessons.new(agent_lessons).merge(lessons))
  end

  def uat_test_ready?
    uat_test_enabled? && uat_url.present?
  end
end
