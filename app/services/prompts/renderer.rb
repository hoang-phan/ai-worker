module Prompts
  class Renderer
    # Names usable as custom `{NAME}` placeholders (workflow variables).
    VARIABLE_NAME = /\A[A-Za-z][A-Za-z0-9_]*\z/
    TOKEN = /\{([A-Za-z][A-Za-z0-9_]*)\}/

    # Every token the renderer substitutes without custom variables, for UI cheatsheets.
    # Guarded by renderer_spec against `built_ins` drifting from this list.
    # Project tokens sit between {SLACK} and {CI_OUTPUT}, as the cheatsheet has always listed them.
    BUILT_IN_TOKENS = begin
      workflow_tokens = WorkflowPlaceholders::TOKENS
      split = workflow_tokens.index("{SLACK}") + 1
      (workflow_tokens.first(split) + ProjectPlaceholders::TOKENS + workflow_tokens.drop(split)).freeze
    end

    def self.render(template_body, workflow)
      new(template_body, workflow).render
    end

    # Every placeholder available for this workflow, token => current value.
    # Single source for what the renderer substitutes (and what the UI can list).
    def self.placeholders_for(workflow)
      new("", workflow).values
    end

    def initialize(template_body, workflow)
      @template_body = template_body
      @workflow = workflow
    end

    def render
      # One pass over the tokens, so a substituted value is never re-scanned for more tokens.
      template_body.gsub(TOKEN) { values.fetch("{#{$1}}", $&) }
    end

    # Custom variables win over the built-ins of the same name only for names the
    # built-ins don't define, so a variable can't hijack {PR}, {JIRA}, ...
    def values
      @values ||= custom_variables.merge(built_ins)
    end

    private

    attr_reader :template_body, :workflow

    def built_ins
      WorkflowPlaceholders.for(workflow).merge(ProjectPlaceholders.for(workflow.project))
    end

    def custom_variables
      workflow.variables.reject { |_name, value| value.to_s.empty? }.to_h { |name, value| [ "{#{name}}", value.to_s ] }
    end
  end
end
