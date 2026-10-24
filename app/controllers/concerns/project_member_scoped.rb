# For member actions routed as /projects/:id/... (brainstorm, slack sync). Loads @project from
# params[:id] before any other before_action in the including controller; unknown ids raise
# ActiveRecord::RecordNotFound (404). Controllers nested under /projects/:project_id use ProjectScoped.
module ProjectMemberScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end
end
