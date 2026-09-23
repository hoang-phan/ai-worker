class Workflow < ApplicationRecord
  belongs_to :project
  has_many :stages, -> { order(:position) }, dependent: :destroy

  enum :status, { active: 0, closed: 1 }

  validates :jira_ticket, presence: true
  validates :branch_name, presence: true
  validates :github_reviewer, presence: true
  validates :github_pr_url, format: { with: %r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/pull/\d+\z}, message: "must be a github.com pull request URL" }, allow_blank: true

  after_create :seed_stages

  # comma-separated skill names entered in the UI, rendered into the {SKILLS} placeholder
  def skill_list
    skills.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def next_stage
    stages.find_by(status: :pending)
  end

  private

  def seed_stages
    stages.create!(stage_type: :implementation, position: 1)
    stages.create!(stage_type: :pr_check, position: 2)
  end
end
