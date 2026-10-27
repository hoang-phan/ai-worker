class WorkflowBulkDeletesController < ApplicationController
  include ProjectScoped

  # Project page "Delete selected": removes the ticked workflows (scoped to this project) in one request.
  def destroy
    workflows = @project.workflows.where(id: Array(params[:workflow_ids]))
    return redirect_to(project_path(@project, status: params[:status].presence), alert: "Select at least one workflow.") if workflows.empty?

    count = workflows.destroy_all.size
    redirect_to project_path(@project, status: params[:status].presence), notice: "Deleted #{count} #{'workflow'.pluralize(count)}."
  end
end
