class WorkflowTestStagesController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow

  # Adds the optional local_test / uat_test stage to this workflow by hand.
  def create
    if @workflow.add_test_stage!(params[:stage_type])
      redirect_to project_workflow_path(@project, @workflow), notice: "Stage added."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "That stage can't be added: it needs the test credentials on the project, a development workflow that hasn't passed that point, and no existing stage."
    end
  end
end
