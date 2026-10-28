require "rails_helper"

RSpec.describe Stages::PrCheckFinish, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "PCF-1", branch_name: "pr-check-finish", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :reviewing, **running_ai_run)
  end
  let(:stage) { build_stage(workflow, :pr_check) }
  let(:github) { instance_double(Github::Client, request_review!: nil) }
  let(:handoff) { instance_double(Stages::ReviewHandoff, reviewers: [ "octocat" ], notify_reviewers!: nil) }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
  end

  it "schedules a retest, clears feedback, and does not notify reviewers" do
    workflow.update!(local_test_feedback: "The login button is broken")
    build_stage(workflow, :local_test)
    allow(project).to receive(:local_test_ready?).and_return(true)

    finish("LOCAL_RETEST: YES\nFIXED_SUMMARY_BEGIN\n- fixed login\nFIXED_SUMMARY_END")

    expect(github).to have_received(:request_review!).with(workflow.github_pr_url, handoff.reviewers)
    expect(workflow.reload).to have_attributes(status: "local_testing", local_test_feedback: nil).and have_finished_ai_run
    expect(stage_actions(stage)).to eq(%w[requested_changes_fixed local_test_retest_scheduled])
    expect(handoff).not_to have_received(:notify_reviewers!)
  end

  it "notifies reviewers with the fixed summary and clears feedback when no retest is needed" do
    workflow.update!(local_test_feedback: "Only a comment change")
    allow(project).to receive(:local_test_ready?).and_return(false)
    output = "LOCAL_RETEST: NO\nFIXED_SUMMARY_BEGIN\n- clarified the comment\nFIXED_SUMMARY_END"

    finish(output)

    expect(github).to have_received(:request_review!).with(workflow.github_pr_url, handoff.reviewers)
    expect(workflow.reload).to have_attributes(status: "reviewing", local_test_feedback: nil)
    expect(stage_actions(stage)).to eq(%w[requested_changes_fixed])
    expect(handoff).to have_received(:notify_reviewers!).with(again: true, fixed: "- clarified the comment")
  end

  describe "agent lessons" do
    before { allow(project).to receive(:local_test_ready?).and_return(false) }

    def lessons_output(*lines) = "LESSONS_BEGIN\n#{lines.map { |l| "- #{l}" }.join("\n")}\nLESSONS_END\nLOCAL_RETEST: NO"

    it "records lessons from the LESSONS block" do
      finish(lessons_output("Prefer services"))

      expect(project.reload.agent_lessons).to eq("Prefer services")
    end

    it "leaves the lessons unchanged when there is no block" do
      project.update!(agent_lessons: "Use partial A")

      finish("LOCAL_RETEST: NO")

      expect(project.reload.agent_lessons).to eq("Use partial A")
    end

    it "does not fail the stage when saving them fails" do
      allow(project).to receive(:update_column).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { finish(lessons_output("Prefer services")) }.not_to raise_error
      expect(stage_actions(stage)).to eq(%w[requested_changes_fixed])
    end
  end
end
