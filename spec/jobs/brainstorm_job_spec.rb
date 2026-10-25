require "rails_helper"

RSpec.describe BrainstormJob, type: :job do
  let(:source_class) { Brainstorm::CycleSource }
  let(:eligible_records) do
    [
      build_personal_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery"),
      build_personal_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery")
    ]
  end
  let(:ineligible_records) do
    [
      build_personal_project(brainstorm_enabled: false, brainstorm_goal: "Improve delivery"),
      build_jira_project(brainstorm_enabled: true, brainstorm_goal: "Improve delivery")
    ]
  end
  let(:log_prefix_for) { ->(record) { "[BrainstormJob] project=#{record.id}" } }
  let(:error_class) { Brainstorm::FetchError }
  let(:failure_observer) do
    ->(record, message = nil) { message ? record.update!(brainstorm_last_result: message) : record.reload.brainstorm_last_result }
  end

  it_behaves_like "an agent sync-cycle job"
end
