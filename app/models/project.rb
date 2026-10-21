class Project < ApplicationRecord
  has_many :workflows, dependent: :destroy
  has_many :jira_syncs, dependent: :destroy
  has_many :bugsnag_syncs, dependent: :destroy

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

  # Swaps `workflow` with its neighbour in the position order (`:up` = earlier = higher priority). Renumbers the
  # whole list 1..n so duplicate positions can't make the move a no-op. Returns false when already at that end.
  def move_workflow(workflow, direction)
    ordered = workflows.order(:position, :id).to_a
    index = ordered.index(workflow)
    target = direction.to_s == "up" ? index - 1 : index + 1
    return false if index.nil? || target.negative? || target >= ordered.size

    ordered[index], ordered[target] = ordered[target], ordered[index]
    transaction { ordered.each.with_index(1) { |w, position| w.update_columns(position: position) unless w.position == position } }
    true
  end

  def local_test_ready?
    jira? && local_test_enabled? && local_url.present?
  end

  # `slack_user_map` is one `github-login=SlackUserID` per line (commas work too), used to tag reviewers in Slack.
  def slack_user_id_for(github_login)
    slack_user_map.to_s.split(/[\n,]+/).each do |entry|
      login, id = entry.split(/[=:]/, 2).map(&:strip)
      return id if id.present? && login.to_s.casecmp?(github_login.to_s.delete_prefix("@"))
    end
    nil
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
