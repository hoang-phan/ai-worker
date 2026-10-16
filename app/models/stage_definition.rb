# A project-level stage of a runbook: copied into every new runbook workflow as
# a Stage, so a workflow keeps its own stages even if the definitions change later.
class StageDefinition < ApplicationRecord
  belongs_to :project

  # agent: run `prompt` as is. message: post the rendered `prompt` to Slack `channel`.
  enum :run_mode, { agent: 0, message: 1 }, prefix: :run

  validates :name, presence: true
  validates :prompt, presence: true
  validates :channel, presence: true, if: :run_message?
end
