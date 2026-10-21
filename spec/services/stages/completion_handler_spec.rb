require "rails_helper"

RSpec.describe Stages::CompletionHandler, type: :service do
  let(:local_directory) { Dir.mktmpdir("completion-handler-spec") }
  let(:project) do
    Project.create!(name: "Completion handler #{SecureRandom.hex(4)}", kind: :jira,
                    repo_full_name: "acme/widgets", local_directory: local_directory)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "DONE-1", branch_name: "completion-handler", github_reviewer: "octocat",
                              github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing,
                              processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log",
                              ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage_type) { :implementation }
  let(:stage) { workflow.stages.create!(stage_type: stage_type, name: stage_type.to_s) }
  let(:github) { double("Github::Client", find_pr_url: "https://github.com/acme/widgets/pull/9", request_review!: nil) }
  let(:git) { class_double(Git::BranchService, push_current!: :pushed) }
  let(:handoff) { double("Stages::ReviewHandoff", enable_auto_merge!: nil, notify_reviewers!: nil, reviewers: [ "octocat" ]) }
  let(:output) { "agent output" }

  def handle(out = output)
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git, handoff: handoff).call(out)
  end

  def actions = stage.stage_runs.order(:id).pluck(:action)

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "clears the AI-run fields on completion" do
    handle
    expect(workflow.reload).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil, ai_started_at: nil, ai_log_offset: 0)
  end

  describe "implementation" do
    it "records the discovered PR, moves to reviewing, enables auto-merge and notifies reviewers" do
      allow(project).to receive(:local_test_ready?).and_return(false)
      handle

      expect(github).to have_received(:find_pr_url).with(branch_name: "completion-handler", jira_ticket: "DONE-1", output: output)
      expect(workflow.reload).to have_attributes(github_pr_url: "https://github.com/acme/widgets/pull/9", status: "reviewing")
      expect(actions).to match_array(%w[ran_implementation])
      expect(handoff).to have_received(:enable_auto_merge!).with("https://github.com/acme/widgets/pull/9")
      expect(handoff).to have_received(:notify_reviewers!).with(no_args)
    end

    it "waits for the local test before auto-merge or notification on development workflows" do
      allow(project).to receive(:local_test_ready?).and_return(true)
      allow(workflow).to receive(:development?).and_return(true)
      handle

      expect(workflow.reload.status).to eq "local_testing"
      expect(handoff).not_to have_received(:enable_auto_merge!)
      expect(handoff).not_to have_received(:notify_reviewers!)
    end
  end

  describe "pr_check" do
    let(:stage_type) { :pr_check }

    it "re-requests review, clears feedback, logs and notifies reviewers again" do
      workflow.update!(local_test_feedback: "old", status: :reviewing)
      allow(project).to receive(:local_test_ready?).and_return(false)
      handle("done\nFIXED: tidied up")

      expect(github).to have_received(:request_review!).with(workflow.github_pr_url, [ "octocat" ])
      expect(workflow.reload).to have_attributes(local_test_feedback: nil, status: "reviewing")
      expect(actions).to match_array(%w[requested_changes_fixed])
      expect(handoff).to have_received(:notify_reviewers!).with(again: true, fixed: anything)
    end

    it "schedules a retest instead of notifying when the policy asks for one" do
      allow(Stages::LocalTestPolicy).to receive(:retest_after_fix?).and_return(true)
      handle

      expect(workflow.reload.status).to eq "local_testing"
      expect(actions).to match_array(%w[requested_changes_fixed local_test_retest_scheduled])
      expect(handoff).not_to have_received(:notify_reviewers!)
    end
  end

  describe "task" do
    let(:stage_type) { :task }

    it "completes the workflow and logs a push" do
      handle
      expect(workflow.reload.status).to eq "done"
      expect(actions).to match_array(%w[task_completed task_pushed])
      expect(git).to have_received(:push_current!).with(project)
    end

    it "does not log a push when nothing was pushed" do
      allow(git).to receive(:push_current!).and_return(:nothing)
      handle
      expect(actions).to match_array(%w[task_completed])
    end

    it "logs a failed push without failing" do
      allow(git).to receive(:push_current!).and_raise(Git::CommandError, "rejected")
      expect { handle }.not_to raise_error
      expect(workflow.reload.status).to eq "done"
      expect(stage.stage_runs.find_by(action: "task_push_failed").error).to eq "rejected"
    end
  end

  describe "pr_review" do
    let(:stage_type) { :pr_review }

    it "marks the workflow done and logs review_completed" do
      handle
      expect(workflow.reload.status).to eq "done"
      expect(actions).to match_array(%w[review_completed])
    end
  end

  describe "uat_test" do
    let(:stage_type) { :uat_test }

    it "completes with a UAT_RESULT line" do
      handle("UAT_RESULT: PASSED")
      expect(workflow.reload.status).to eq "uat_tested"
      expect(actions).to match_array(%w[uat_test_completed])
    end

    it "raises without a UAT_RESULT line" do
      expect { handle }.to raise_error(AiCli::CommandError, /UAT_RESULT/)
    end
  end

  describe "local_test" do
    let(:stage_type) { :local_test }
    let(:local_test_finish) { instance_double(Stages::LocalTestFinish, call: nil) }

    it "delegates to LocalTestFinish" do
      allow(Stages::LocalTestFinish).to receive(:new).and_return(local_test_finish)
      handle

      expect(Stages::LocalTestFinish).to have_received(:new).with(workflow: workflow, stage: stage, handoff: handoff)
      expect(local_test_finish).to have_received(:call).with(output)
    end
  end

  describe "runbook_step" do
    let(:stage_type) { :runbook_step }

    it "parks the workflow waiting for Next and merges agent variables" do
      handle("VAR: VERSION=1.2.3")

      expect(workflow.reload).to have_attributes(status: "waiting", awaiting_next: true)
      expect(workflow.variables).to include("VERSION" => "1.2.3")
      expect(actions).to match_array(%w[stage_completed])
    end
  end
end
