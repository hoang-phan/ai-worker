class AgentDelegation < ApplicationRecord
  belongs_to :agent
  belongs_to :delegate, class_name: "Agent"

  validates :delegate_id, uniqueness: { scope: :agent_id }
end
