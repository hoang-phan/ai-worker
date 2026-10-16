# Additive only: new columns with safe defaults, no data is touched. Existing runbook stages keep the old
# behaviour (stop for Next after every stage, no check).
class AddRunbookAutomation < ActiveRecord::Migration[8.1]
  def change
    # Stage: continue to the next stage by itself once this one succeeds; hold until a GitHub Actions workflow finished.
    add_column :stages, :auto_advance, :boolean, null: false, default: false
    add_column :stages, :wait_for_workflow, :string
    # Workflow: the scheduler may start the current runbook stage without a click (set by Run / Next, cleared on a pause or failure).
    add_column :workflows, :auto_run, :boolean, null: false, default: false
  end
end
