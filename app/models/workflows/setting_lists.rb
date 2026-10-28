module Workflows
  # Parses the comma- and whitespace-separated workflow settings entered in the UI.
  class SettingLists
    def initialize(workflow)
      @workflow = workflow
    end

    # Comma-separated skill names rendered into the {SKILLS} placeholder.
    def skill_list = comma_list(workflow.skills)

    # Same format as `skills`, rendered into {PR_SKILLS}.
    def pr_skill_list = comma_list(workflow.pr_skills)

    # `github_reviewer` holds usernames separated by commas and/or whitespace.
    def reviewer_list
      workflow.github_reviewer.to_s.split(/[,\s]+/).reject(&:blank?).uniq
    end

    private

    attr_reader :workflow

    def comma_list(value) = value.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
