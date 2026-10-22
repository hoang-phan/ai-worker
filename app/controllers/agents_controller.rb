class AgentsController < ApplicationController
  include ProjectScoped

  before_action :set_agent, only: %i[edit update destroy]

  def new
    @agent = @project.agents.new
  end

  def edit
  end

  def create
    @agent = @project.agents.new(agent_params)
    if @agent.save
      redirect_to @project, notice: "Agent created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @agent.update(agent_params)
      redirect_to @project, notice: "Agent updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agent.destroy
    redirect_to @project, notice: "Agent deleted."
  end

  private

  def set_agent
    @agent = @project.agents.find(params[:id])
  end

  # delegate_ids is limited to this project's agents so a forged id can't link another project's agent.
  def agent_params
    permitted = params.require(:agent).permit(:name, :description, :instructions, :model, :effort, :provider, :allowed_tools_text, delegate_ids: [])
    permitted[:delegate_ids] = @project.agents.where(id: permitted[:delegate_ids]).ids if permitted.key?(:delegate_ids)
    permitted
  end
end
