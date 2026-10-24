module StagesHelper
  def stage_run_mode_options
    Stage.run_modes.keys.map do |run_mode|
      [ run_mode == "agent" ? "Run the prompt with the agent" : "Post the text to Slack", run_mode ]
    end
  end

  def stage_template_options(stage)
    stage.candidate_templates.map { |template| [ template.name, template.id, { data: { body: template.body } } ] }
  end
end
