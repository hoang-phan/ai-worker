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

  # UAT login the agent types into the browser during the post-UAT test; stored encrypted.
  encrypts :uat_password
  # Login for the local (development server) test that runs before review; stored encrypted too.
  encrypts :local_password

  validates :uat_url, format: { with: %r{\Ahttps?://[^/\s]+\S*\z}, message: "must be a full URL like https://uat.example.com" }, allow_blank: true
  validates :uat_test_delay_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :uat_url, presence: true, if: :uat_test_enabled?
  validates :ci_command, presence: { message: "is required for the ci_loop flow" }, if: :flow_ci_loop?
  validates :flow, inclusion: { in: %w[standard], message: "ci_loop needs a Jira project" }, unless: :jira?
  validates :ci_max_rounds, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }

  validates :local_url, format: { with: %r{\Ahttps?://[^/\s]+\S*\z}, message: "must be a full URL like http://localhost:3000" }, allow_blank: true
  validates :local_url, presence: true, if: :local_test_enabled?

  # True when `local_directory` is the checkout this app is running from. Agents
  # branch/pull/merge and may migrate in the project's clone, which would swap
  # the live code and hit the live dev DB — self-evolving needs its own clone.
  def runs_from_live_checkout?
    return false if local_directory.blank?

    File.realpath(File.expand_path(local_directory)) == File.realpath(Rails.root)
  rescue Errno::ENOENT
    false
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

  def local_test_ready?
    jira? && local_test_enabled? && local_url.present?
  end

  # `slack_user_map` is one `github-login=SlackUserID` per line (commas work too), used to tag reviewers in Slack.
  def slack_user_id_for(github_login)
    Projects::SlackUserMap.new(slack_user_map).slack_id_for(github_login)
  end

  def uat_test_ready?
    uat_test_enabled? && uat_url.present?
  end

  validates :slack_review_channel, format: { with: /\A[CG][A-Z0-9]{8,}\z/, message: "must be a Slack channel ID like C0B5XFY2F0T" }, allow_blank: true

  validates :jira_base_url, format: { with: %r{\Ahttps://[^/\s]+\z}, message: "must look like https://your-site.atlassian.net" }, allow_blank: true
  validates :brainstorm_goal, presence: true, if: :brainstorm_enabled?
  validates :brainstorm_max_workflows, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }
  validates :name, presence: true
  validates :local_directory, presence: true
  validate :local_directory_is_not_the_running_app
  validates :repo_full_name, presence: true, format: { with: %r{\A[^/\s]+/[^/\s]+\z}, message: "must be in the form org/repo" }, if: :jira?

  private

  def local_directory_is_not_the_running_app
    return unless runs_from_live_checkout?

    errors.add(:local_directory, "is this app's own live checkout; use a separate clone (see docs/ADDING_A_PROJECT.md)")
  end
end
