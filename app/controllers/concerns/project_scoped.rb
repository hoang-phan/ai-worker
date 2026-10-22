# For controllers nested under /projects/:project_id. Loads @project before any
# other before_action in the including controller; unknown ids raise
# ActiveRecord::RecordNotFound (404).
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
