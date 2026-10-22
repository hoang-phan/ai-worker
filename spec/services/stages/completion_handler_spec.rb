require "rails_helper"

RSpec.describe Stages::CompletionHandler, type: :service do
  let(:local_directory) { Dir.mktmpdir("completion-handler-spec") }
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "DONE-1", branch_name: "completion-handler", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing,
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

  describe "implementation" do
    let(:implementation_finish) { instance_double(Stages::ImplementationFinish, call: nil) }

    it "delegates to ImplementationFinish" do
      allow(Stages::ImplementationFinish).to receive(:new).and_return(implementation_finish)
      handle

      expect(Stages::ImplementationFinish).to have_received(:new).with(
        workflow: workflow, stage: stage, project: project, github: github, handoff: handoff
      )
      expect(implementation_finish).to have_received(:call).with(output)
    end
  end

  describe "pr_check" do
    let(:stage_type) { :pr_check }
    let(:pr_check_finish) { instance_double(Stages::PrCheckFinish, call: nil) }

    it "delegates to PrCheckFinish" do
      allow(Stages::PrCheckFinish).to receive(:new).and_return(pr_check_finish)
      handle

      expect(Stages::PrCheckFinish).to have_received(:new).with(
        workflow: workflow, stage: stage, project: project, github: github, handoff: handoff
      )
      expect(pr_check_finish).to have_received(:call).with(output)
    end
  end

  describe "task" do
    let(:stage_type) { :task }
    let(:task_finish) { instance_double(Stages::TaskFinish, call: nil) }

    it "delegates to TaskFinish" do
      allow(Stages::TaskFinish).to receive(:new).and_return(task_finish)
      handle

      expect(Stages::TaskFinish).to have_received(:new).with(workflow: workflow, stage: stage, project: project, git: git)
      expect(task_finish).to have_received(:call).with(output)
    end
  end

  describe "pr_review" do
    let(:stage_type) { :pr_review }
    let(:pr_review_finish) { instance_double(Stages::PrReviewFinish, call: nil) }

    it "delegates to PrReviewFinish" do
      allow(Stages::PrReviewFinish).to receive(:new).and_return(pr_review_finish)
      handle

      expect(Stages::PrReviewFinish).to have_received(:new).with(workflow: workflow, stage: stage)
      expect(pr_review_finish).to have_received(:call).with(output)
    end
  end

  describe "jira_update" do
    let(:stage_type) { :jira_update }
    let(:jira_lifecycle_finish) { instance_double(Stages::JiraLifecycleFinish, call: nil) }

    it "delegates to JiraLifecycleFinish" do
      allow(Stages::JiraLifecycleFinish).to receive(:new).and_return(jira_lifecycle_finish)
      handle

      expect(Stages::JiraLifecycleFinish).to have_received(:new).with(workflow: workflow, stage: stage, project: project)
      expect(jira_lifecycle_finish).to have_received(:call).with(output)
    end

    it "propagates a missing JIRA_RESULT error" do
      expect { handle }.to raise_error(AiCli::CommandError, /JIRA_RESULT/)
    end
  end

  describe "uat_test" do
    let(:stage_type) { :uat_test }
    let(:jira_lifecycle_finish) { instance_double(Stages::JiraLifecycleFinish, call: nil) }

    it "delegates to JiraLifecycleFinish" do
      allow(Stages::JiraLifecycleFinish).to receive(:new).and_return(jira_lifecycle_finish)
      handle

      expect(Stages::JiraLifecycleFinish).to have_received(:new).with(workflow: workflow, stage: stage, project: project)
      expect(jira_lifecycle_finish).to have_received(:call).with(output)
    end

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
    let(:runbook_step_finish) { instance_double(Stages::RunbookStepFinish, call: nil) }

    it "delegates to RunbookStepFinish" do
      allow(Stages::RunbookStepFinish).to receive(:new).and_return(runbook_step_finish)
      handle

      expect(Stages::RunbookStepFinish).to have_received(:new).with(workflow: workflow, stage: stage)
      expect(runbook_step_finish).to have_received(:call).with(output)
    end
  end
end
