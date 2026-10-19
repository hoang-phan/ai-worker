class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy sync_slack brainstorm]

  def index
    @projects = Project.order(:name)
  end

  def show
    @workflows = @project.workflows.order(:position)
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

  # Asks the agent to look for new Slack mentions with PRs right now instead of
  # waiting for the next 30-minute fetch; SlackReviewJob imports the result.
  def sync_slack
    sync = Slack::ReviewSync.new(@project)
    if sync.blockers.any?
      redirect_to @project, alert: "Slack sync blocked: #{sync.blockers.join('; ')}"
    elsif sync.fetcher.start
      redirect_to @project, notice: "Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing."
    else
      redirect_to @project, alert: "A Slack fetch is already running for this project."
    end
  rescue AiCli::CommandError => e
    redirect_to @project, alert: "Slack sync failed: #{e.message}"
  end

  # Runs a brainstorm now instead of waiting for the hourly one. Like the scheduled run it only happens while
  # the project has no pending workflow; BrainstormJob imports the result as pending workflows.
  def brainstorm
    planner = Brainstorm::Planner.new(@project)
    if planner.blockers.any?
      redirect_to @project, alert: "Brainstorm blocked: #{planner.blockers.join('; ')}"
    elsif planner.queued_count.positive?
      redirect_to @project, alert: "Brainstorm skipped: #{planner.queued_count} workflow(s) still pending; start or delete them first."
    elsif planner.start
      @project.update(brainstorm_last_run_at: Time.current)
      redirect_to @project, notice: "Agent is brainstorming workflows. They appear within the hour after it finishes."
    else
      redirect_to @project, alert: "A brainstorm is already running for this project."
    end
  rescue AiCli::CommandError => e
    redirect_to @project, alert: "Brainstorm failed: #{e.message}"
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :local_directory, :repo_full_name, :kind, :default_skills, :default_reviewers, :ci_instructions,
      :jira_base_url, :jira_assignee, :jira_tester, :slack_review_enabled, :slack_mention, :slack_review_channel, :slack_user_map,
      :uat_test_enabled, :uat_url, :test_instructions, :uat_instructions, :uat_username, :uat_password, :uat_test_delay_minutes,
      :brainstorm_enabled, :brainstorm_goal, :brainstorm_auto_start, :brainstorm_max_workflows,
      :local_test_enabled, :local_url, :local_instructions, :local_username, :local_password).tap do |permitted|
      # The password field is never filled in; blank means "keep the saved one".
      permitted.delete(:uat_password) if permitted[:uat_password].blank?
      permitted.delete(:local_password) if permitted[:local_password].blank?
    end
  end
end
