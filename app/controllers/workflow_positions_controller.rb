class WorkflowPositionsController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow

  # Up/down arrows on the project page: reorders the priority list (the scheduler works through workflows by position).
  def move
    direction = params[:direction].to_s
    return redirect_to @project, alert: "Unknown direction." unless %w[up down].include?(direction)

    Projects::WorkflowReorder.new(@project).move(@workflow, direction)
    redirect_to project_path(@project, status: params[:status].presence)
  end
end
