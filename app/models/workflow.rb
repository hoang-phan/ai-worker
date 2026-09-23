class Workflow < ApplicationRecord
  belongs_to :project
  has_many :stages, dependent: :destroy

  enum :status, { pending: 0, implementing: 1, reviewing: 2, done: 3 }

  # which stage type is currently active for each in-flight workflow status
  STAGE_TYPE_BY_STATUS = { "implementing" => "implementation", "reviewing" => "pr_check" }.freeze

  validates :jira_ticket, presence: true
  validates :branch_name, presence: true
  validates :github_reviewer, presence: true
  validates :github_pr_url, format: { with: %r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/pull/\d+\z}, message: "must be a github.com pull request URL" }, allow_blank: true

  after_create :seed_stages

  # comma-separated skill names entered in the UI, rendered into the {SKILLS} placeholder
  def skill_list
    skills.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def current_stage
    stage_type = STAGE_TYPE_BY_STATUS[status]
    return nil unless stage_type

    stages.find_by(stage_type: stage_type)
  end

  private

  def seed_stages
    stages.create!(stage_type: :implementation)
    stages.create!(stage_type: :pr_check)
  end
end
