class Project < ApplicationRecord
  has_many :workflows, dependent: :destroy

  # team: GitHub-backed projects that go through branch/PR/review stages.
  # personal: local-only projects where each workflow is a single task
  # description that gets implemented and committed directly, no PR involved.
  enum :kind, { team: 0, personal: 1 }

  validates :name, presence: true
  validates :local_directory, presence: true
  validates :repo_full_name, presence: true, format: { with: %r{\A[^/\s]+/[^/\s]+\z}, message: "must be in the form org/repo" }, if: :team?
end
