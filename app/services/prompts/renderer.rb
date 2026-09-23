module Prompts
  class Renderer
    def self.render(template_body, workflow)
      new(template_body, workflow).render
    end

    def initialize(template_body, workflow)
      @template_body = template_body
      @workflow = workflow
    end

    def render
      template_body
        .gsub("{JIRA}", workflow.jira_ticket.to_s)
        .gsub("{PR}", workflow.github_pr_url.to_s)
        .gsub("{REVIEWER}", workflow.github_reviewer.to_s)
        .gsub("{SKILLS}", workflow.skill_list.join(", "))
    end

    private

    attr_reader :template_body, :workflow
  end
end
