# Shared by the controllers acting on one workflow under /projects/:project_id/workflows/:id, and by
# StagesController under /projects/:project_id/workflows/:workflow_id/stages. Provides #set_workflow; the
# including controller registers it with its own before_action, after ProjectScoped. Nested controllers
# override #workflow_id_param (default params[:id]) to read the parent key instead.
module WorkflowScoped
  extend ActiveSupport::Concern

  private

  def set_workflow
    @workflow = @project.workflows.find(workflow_id_param)
  end

  def workflow_id_param
    params[:id]
  end
end
