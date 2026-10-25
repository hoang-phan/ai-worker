require "rails_helper"

RSpec.describe SlackReviewJob, type: :job do
  let(:source_class) { Slack::ReviewCycleSource }
  let(:eligible_records) do
    [ build_jira_project(slack_review_enabled: true), build_jira_project(slack_review_enabled: true) ]
  end
  let(:ineligible_records) do
    [ build_jira_project(slack_review_enabled: false), build_personal_project(slack_review_enabled: true) ]
  end
  let(:log_prefix_for) { ->(record) { "[SlackReviewJob] project=#{record.id}" } }
  let(:error_class) { Slack::FetchError }
  let(:failure_observer) do
    ->(record, message = nil) { message ? record.update!(slack_last_result: message) : record.reload.slack_last_result }
  end

  it_behaves_like "an agent sync-cycle job"
end
