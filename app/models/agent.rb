# A project-specific specialist: knows one project or feature group, runs with its own
# model/effort and may hand work to the agents it delegates to. Unlike a PromptTemplate
# (generic text reused across projects) an agent belongs to exactly one project.
class Agent < ApplicationRecord
  belongs_to :project
  has_many :stages, dependent: :nullify
  has_many :agent_delegations, dependent: :destroy
  has_many :delegates, through: :agent_delegations
  has_many :delegating_links, class_name: "AgentDelegation", foreign_key: :delegate_id, dependent: :destroy, inverse_of: :delegate

  EFFORTS = %w[low medium high xhigh max].freeze
  MODEL_FORMAT = /\A[\w.\-\[\]]+\z/
  NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

  validates :name, presence: true, uniqueness: { scope: :project_id },
                   format: { with: NAME_FORMAT, message: "must be lowercase letters, digits and dashes, e.g. billing-expert" }
  validates :description, presence: true
  validates :effort, inclusion: { in: EFFORTS }, allow_blank: true
  validates :model, format: { with: MODEL_FORMAT }, allow_blank: true
  validates :provider, inclusion: { in: ->(_) { AiCli::Providers.names } }, allow_blank: true
  validate :delegates_belong_to_project

  # One tool rule per line (e.g. `Read`, `Bash(git log:*)`); blank lines and repeats are dropped. Empty means no
  # restriction. Only providers with tool lists enforce it; the prompt states it for the others.
  def allowed_tools_text
    allowed_tools.join("\n")
  end

  def allowed_tools_text=(text)
    self.allowed_tools = text.to_s.lines.map(&:strip).reject(&:empty?).uniq
  end

  # Agents of the project this one may hand work to (every other one); a new agent's nil id excludes nothing.
  def delegate_candidates = project.agents.where.not(id: id).order(:name)

  private

  def delegates_belong_to_project
    delegates.each do |delegate|
      errors.add(:delegates, "must belong to the same project") unless delegate.project_id == project_id
      errors.add(:delegates, "cannot include the agent itself") if delegate == self
    end
  end
end
