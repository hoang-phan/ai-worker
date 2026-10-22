class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy]

  def index
    @projects = Project.order(:name)
  end

  def show
    @workflows = @project.workflows.order(:position, :id)
    @logged_seconds = TimeLog.seconds_by_ticket(@workflows.filter_map(&:jira_key))
  end

  def new
    @project = Project.new
  end

  def edit
  end

  def create
    @project = Project.new(project_params)
    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :local_directory, :repo_full_name, :kind, :default_skills, :default_pr_skills, :default_reviewers, :ci_instructions,
      :jira_base_url, :jira_assignee, :jira_tester, :slack_review_enabled, :slack_mention, :slack_review_channel, :slack_user_map,
      :uat_test_enabled, :uat_url, :test_instructions, :uat_instructions, :uat_username, :uat_password, :uat_test_delay_minutes,
      :brainstorm_enabled, :brainstorm_goal, :brainstorm_auto_start, :brainstorm_max_workflows,
      :agent_lessons, :ci_command, :ci_max_rounds, :ci_verify_instructions, :flow, :pr_instructions,
      :local_test_enabled, :local_url, :local_instructions, :local_username, :local_password).tap do |permitted|
      # The password field is never filled in; blank means "keep the saved one".
      permitted.delete(:uat_password) if permitted[:uat_password].blank?
      permitted.delete(:local_password) if permitted[:local_password].blank?
    end
  end
end
