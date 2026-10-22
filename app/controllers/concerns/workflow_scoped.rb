# Shared by the controllers acting on one workflow under /projects/:project_id/workflows/:id. Provides
# #set_workflow; the including controller registers it with its own before_action, after ProjectScoped.
module WorkflowScoped
  extend ActiveSupport::Concern

  private

  def set_workflow
    @workflow = @project.workflows.find(params[:id])
  end
end
