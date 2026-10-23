class JiraSyncsController < ApplicationController
  include ProjectScoped
  include ProjectChildCrud

  project_child_crud association: :jira_syncs, flash_label: "Jira sync"

  private

  def jira_sync_params
    params.require(:jira_sync).permit(:jira_project, :parent_ticket, :auto_sync)
  end
end
