require "rails_helper"
require "tmpdir"

RSpec.describe WorkflowSchedulerJob, type: :job do
  let(:directories) { [] }
  let(:calls) { [] }
  let(:merge_checks) { [] }
  let(:starting_workflow_ids) { [] }
  let(:failing_workflow_ids) { [] }
  let(:max_agents) { 3 }

  after do
    directories.each do |directory|
      FileUtils.remove_entry(directory) if directory.start_with?(Dir.tmpdir) && File.exist?(directory)
    end
  end

  before do
    allow(described_class).to receive(:max_concurrent_agents).and_return(max_agents)
    allow(Rails.logger).to receive(:error)
    allow(StageExecutor).to receive(:new) do |workflow, _stage|
      executor = instance_double(StageExecutor)
      allow(executor).to receive(:call) do
        calls << workflow.id
        raise "executor failed" if failing_workflow_ids.include?(workflow.id)

        workflow.update!(processing: true) if starting_workflow_ids.include?(workflow.id)
      end
      executor
    end
    allow(Github::Client).to receive(:new)
    allow(Stages::MergeCheck).to receive(:new) do |workflow:, **|
      instance_double(Stages::MergeCheck, call: merge_checks << workflow.id)
    end
  end

  def project(kind: :personal, directory: nil)
    directory ||= Dir.mktmpdir("workflow-scheduler-job-spec")
    directories << directory unless directories.include?(directory)
    attributes = { name: "Scheduler spec #{SecureRandom.hex(4)}", kind: kind, local_directory: directory }
    attributes[:repo_full_name] = "acme/widgets" if kind == :jira
    Project.create!(**attributes)
  end

  def workflow(project:, status: :implementing, kind: :development, position: 1, **attributes)
    attributes[:task_description] = "Task #{SecureRandom.hex(4)}" if kind == :development && project.personal?
    if kind == :development && project.jira?
      attributes.reverse_merge!(jira_ticket: "SPEC-#{SecureRandom.random_number(10_000)}", branch_name: "spec-#{SecureRandom.hex(4)}", github_reviewer: "reviewer")
    end
    attributes[:github_pr_url] ||= "https://github.com/acme/widgets/pull/#{SecureRandom.random_number(10_000)}" if kind == :pr_review
    project.workflows.create!(status: status, kind: kind, position: position, **attributes)
  end

  it "delegates the active-workflow phase to ActiveWorkflowRunner" do
    runner = instance_double(Scheduling::ActiveWorkflowRunner, call: nil)
    allow(Scheduling::ActiveWorkflowRunner).to receive(:new).with(max_capacity: max_agents).and_return(runner)

    described_class.perform_now(42)

    expect(runner).to have_received(:call).with(42)
  end

  it "polls processing workflows before starting waiting workflows" do
    running = workflow(project: project, position: 1, processing: true)
    waiting = workflow(project: project, position: 2)

    described_class.perform_now

    expect(calls).to eq([ running.id, waiting.id ])
  end

  it "starts only one waiting workflow for a shared clone" do
    directory = Dir.mktmpdir("workflow-scheduler-shared-clone")
    first = workflow(project: project(directory: directory), position: 1)
    second = workflow(project: project(directory: "#{directory}/./"), position: 2)

    described_class.perform_now

    expect(calls).to eq([ first.id ])
    expect(calls).not_to include(second.id)
  end

  context "with one agent slot" do
    let(:max_agents) { 1 }

    it "does not exceed max concurrency" do
      first = workflow(project: project, position: 1)
      second = workflow(project: project, position: 2)
      starting_workflow_ids.concat([ first.id, second.id ])

      described_class.perform_now

      expect(calls).to eq([ first.id ])
      expect(Workflow.where(processing: true).count).to eq(1)
    end
  end

  it "logs one executor failure and continues with the next workflow" do
    failed = workflow(project: project, position: 1)
    following = workflow(project: project, position: 2)
    failing_workflow_ids << failed.id

    described_class.perform_now

    expect(calls).to eq([ failed.id, following.id ])
    expect(Rails.logger).to have_received(:error).with(/workflow=#{failed.id} RuntimeError: executor failed/)
  end

  describe "the post-merge phase" do
    it "delegates to PostMergePhase" do
      phase = instance_double(Scheduling::PostMergePhase, call: nil)
      allow(Scheduling::PostMergePhase).to receive(:new).and_return(phase)

      described_class.perform_now

      expect(phase).to have_received(:call)
    end

    it "confirms merges and starts one merged workflow when idle" do
      done = workflow(project: project(kind: :jira), status: :done, github_pr_url: "https://github.com/acme/widgets/pull/2", position: 1)
      done.stages.create!(stage_type: :pr_check)
      first_merged = workflow(project: project(kind: :jira), status: :merged, position: 2)
      second_merged = workflow(project: project(kind: :jira), status: :merged, position: 3)

      described_class.perform_now

      expect(merge_checks).to eq([ done.id ])
      expect(calls).to include(first_merged.id)
      expect(calls).not_to include(second_merged.id)
    end
  end

  describe "the UAT phase" do
    it "delegates to UatPhase with the max concurrency" do
      phase = instance_double(Scheduling::UatPhase, call: nil)
      allow(Scheduling::UatPhase).to receive(:new).with(max_capacity: max_agents).and_return(phase)

      described_class.perform_now

      expect(phase).to have_received(:call)
    end

    it "moves due UAT workflows to testing and retries idle tests using free slots" do
      busy = workflow(project: project, processing: true)
      due = workflow(project: project(kind: :jira), status: :uat_waiting, uat_test_at: 1.minute.ago, position: 1)
      retrying = workflow(project: project(kind: :jira), status: :uat_testing, position: 2)

      described_class.perform_now

      expect(calls).to include(busy.id, due.id, retrying.id)
      expect(due.reload).to be_uat_testing
      expect(retrying.reload).to be_uat_testing
    end
  end

  it "starts a named non-auto-run runbook" do
    runbook = workflow(project: project, kind: :runbook, status: :implementing, auto_run: false)
    stage = runbook.stages.create!(stage_type: :runbook_step, name: "Deploy", position: 1)
    runbook.update!(current_stage_id: stage.id)

    described_class.perform_now(runbook.id)

    expect(calls).to eq([ runbook.id ])
  end
end
