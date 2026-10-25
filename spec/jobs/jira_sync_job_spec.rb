require "rails_helper"

RSpec.describe JiraSyncJob, type: :job do
  let(:source_class) { Jira::SyncCycleSource }
  let(:eligible_records) do
    project = build_jira_project(jira_base_url: "https://acme.atlassian.net")
    [ project.jira_syncs.create!, project.jira_syncs.create! ]
  end
  let(:ineligible_records) do
    [ build_jira_project(jira_base_url: nil).jira_syncs.create!, build_personal_project.jira_syncs.create! ]
  end
  let(:log_prefix_for) { ->(record) { "[JiraSyncJob] jira_sync=#{record.id}" } }
  let(:error_class) { Jira::FetchError }
  let(:failure_observer) do
    ->(record, message = nil) { message ? record.update!(last_result: message) : record.reload.last_result }
  end

  it_behaves_like "an agent sync-cycle job"
end
