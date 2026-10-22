class PromptTemplate < ApplicationRecord
  has_many :stages, dependent: :nullify

  EFFORTS = %w[low medium high xhigh max].freeze
  MODEL_FORMAT = /\A[\w.\-\[\]]+\z/

  enum :stage_type, Stage::STAGE_TYPES

  validates :name, presence: true
  validates :body, presence: true
  validates :effort, inclusion: { in: EFFORTS }, allow_blank: true
  validates :model, format: { with: MODEL_FORMAT }, allow_blank: true
end
