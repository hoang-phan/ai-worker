require "rails_helper"

RSpec.describe BugsnagSyncJob, type: :job do
  let(:source_class) { Bugsnag::SyncCycleSource }
  let(:eligible_records) do
    [
      build_jira_project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "WEB"),
      build_personal_project.bugsnag_syncs.create!(bugsnag_project: "api", jira_project: "API", auto_sync: false)
    ]
  end
  let(:ineligible_records) { [] }
  let(:log_prefix_for) { ->(record) { "[BugsnagSyncJob] bugsnag_sync=#{record.id}" } }
  let(:error_class) { Bugsnag::FetchError }
  let(:failure_observer) do
    ->(record, message = nil) { message ? record.update!(last_result: message) : record.reload.last_result }
  end

  it_behaves_like "an agent sync-cycle job"
end
