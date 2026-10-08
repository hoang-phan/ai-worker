class Project < ApplicationRecord
  has_many :workflows, dependent: :destroy
  has_many :jira_syncs, dependent: :destroy

  # jira: GitHub-backed projects driven by Jira tickets; they go through
  # branch/PR/review stages, and can optionally pull workflows from Jira.
  # personal: local-only projects where each workflow is a single task
  # description that gets implemented and committed directly, no PR involved.
  enum :kind, { jira: 0, personal: 1 }

  validates :jira_base_url, format: { with: %r{\Ahttps://[^/\s]+\z}, message: "must look like https://your-site.atlassian.net" }, allow_blank: true
  validates :name, presence: true
  validates :local_directory, presence: true
  validates :repo_full_name, presence: true, format: { with: %r{\A[^/\s]+/[^/\s]+\z}, message: "must be in the form org/repo" }, if: :jira?
end
