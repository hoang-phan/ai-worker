class AgentsController < ApplicationController
  include ProjectScoped
  include ProjectChildCrud

  project_child_crud association: :agents, flash_label: "Agent"

  private

  # delegate_ids is limited to this project's agents so a forged id can't link another project's agent.
  def agent_params
    permitted = params.require(:agent).permit(:name, :description, :instructions, :model, :effort, :provider, :allowed_tools_text, delegate_ids: [])
    permitted[:delegate_ids] = @project.agents.where(id: permitted[:delegate_ids]).ids if permitted.key?(:delegate_ids)
    permitted
  end
end
