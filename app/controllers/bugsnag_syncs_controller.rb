class BugsnagSyncsController < ApplicationController
  include ProjectScoped
  include ProjectChildCrud

  project_child_crud association: :bugsnag_syncs, flash_label: "Bugsnag sync"

  private

  def bugsnag_sync_params
    params.require(:bugsnag_sync).permit(:bugsnag_project, :jira_project, :min_events, :max_tickets, :auto_sync)
  end
end
