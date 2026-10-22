class PromptTemplate < ApplicationRecord
  has_many :stages, dependent: :nullify

  enum :stage_type, Stage::STAGE_TYPES

  validates :name, presence: true
  validates :body, presence: true

end
