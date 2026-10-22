class WorkflowTimeLogsController < ApplicationController
  include ProjectScoped

  # Batch "Log time" buttons (project page) and the single-workflow buttons (workflow page): each selected
  # workflow gets one worklog of `hours`, placed on the next available weekday (see Jira::TimeSlotPlanner).
  def create
    hours = params[:hours].to_f
    return redirect_back_or_to(@project, alert: "Pick one of #{Jira::TimeLogger::PRESET_HOURS.join(', ')} hours.") unless Jira::TimeLogger::PRESET_HOURS.include?(hours)

    workflows = @project.workflows.where(id: Array(params[:workflow_ids])).order(:position, :id)
    return redirect_back_or_to(@project, alert: "Select at least one workflow.") if workflows.empty?

    result = Jira::TimeLogBatch.new.call(workflows, hours)
    redirect_back_or_to @project, (result.success? ? :notice : :alert) => result.message(hours)
  end
end
