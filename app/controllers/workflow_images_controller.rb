class WorkflowImagesController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow

  def destroy_image
    @workflow.remove_image(params[:name])
    redirect_back_or_to edit_project_workflow_path(@project, @workflow), notice: "Image removed."
  end
end
