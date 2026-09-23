class Project < ApplicationRecord
  has_many :workflows, dependent: :destroy

  validates :name, presence: true
  validates :local_directory, presence: true
  validates :repo_full_name, presence: true, format: { with: %r{\A[^/\s]+/[^/\s]+\z}, message: "must be in the form org/repo" }
end
