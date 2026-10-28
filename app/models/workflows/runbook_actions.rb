module Workflows
  # Preserves Workflow's runbook-specific public names over RunbookNavigator's concise API.
  class RunbookActions
    def initialize(navigator)
      @navigator = navigator
    end

    def start_runbook! = navigator.start!

    def advance! = navigator.advance!

    def next_runbook_stage = navigator.next_stage

    def previous_runbook_stage = navigator.previous_stage

    private

    attr_reader :navigator
  end
end
