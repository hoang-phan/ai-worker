require "rails_helper"

RSpec.describe Stages::PrCheckFinish, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "PCF-1", branch_name: "pr-check-finish", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :reviewing,
                                 processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log",
                                 ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage) { workflow.stages.create!(stage_type: :pr_check, name: "pr_check") }
  let(:github) { double("Github::Client", request_review!: nil) }
  let(:handoff) { double("Stages::ReviewHandoff", reviewers: [ "octocat" ], notify_reviewers!: nil) }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  it "schedules a retest, clears feedback, and does not notify reviewers" do
    workflow.update!(local_test_feedback: "The login button is broken")
    workflow.stages.create!(stage_type: :local_test, name: "local_test")
    allow(project).to receive(:local_test_ready?).and_return(true)

    finish("LOCAL_RETEST: YES\nFIXED_SUMMARY_BEGIN\n- fixed login\nFIXED_SUMMARY_END")

    expect(github).to have_received(:request_review!).with(workflow.github_pr_url, handoff.reviewers)
    expect(workflow.reload).to have_attributes(status: "local_testing", local_test_feedback: nil,
                                                processing: false, ai_pid: nil, ai_log_path: nil,
                                                ai_started_at: nil, ai_log_offset: 0)
    expect(actions).to eq(%w[requested_changes_fixed local_test_retest_scheduled])
    expect(handoff).not_to have_received(:notify_reviewers!)
  end

  it "notifies reviewers with the fixed summary and clears feedback when no retest is needed" do
    workflow.update!(local_test_feedback: "Only a comment change")
    allow(project).to receive(:local_test_ready?).and_return(false)
    output = "LOCAL_RETEST: NO\nFIXED_SUMMARY_BEGIN\n- clarified the comment\nFIXED_SUMMARY_END"

    finish(output)

    expect(github).to have_received(:request_review!).with(workflow.github_pr_url, handoff.reviewers)
    expect(workflow.reload).to have_attributes(status: "reviewing", local_test_feedback: nil)
    expect(actions).to eq(%w[requested_changes_fixed])
    expect(handoff).to have_received(:notify_reviewers!).with(again: true, fixed: "- clarified the comment")
  end
end
