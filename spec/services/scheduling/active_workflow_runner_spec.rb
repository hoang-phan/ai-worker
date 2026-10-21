require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::ActiveWorkflowRunner do
  let(:directories) { [] }
  let(:calls) { [] }
  let(:starting_ids) { [] }
  let(:failing_ids) { [] }
  let(:logger) { instance_double(Logger, error: nil) }
  let(:max) { 3 }
  let(:executor) do
    lambda do |workflow|
      calls << workflow.id
      raise "executor failed" if failing_ids.include?(workflow.id)

      workflow.update!(processing: true) if starting_ids.include?(workflow.id)
    end
  end
  let(:runner) { described_class.new(executor: executor, logger: logger, max_capacity: max) }

  after do
    directories.each { |d| FileUtils.remove_entry(d) if d.start_with?(Dir.tmpdir) && File.exist?(d) }
  end

  def project(directory: nil, kind: :personal)
    directory ||= Dir.mktmpdir("active-workflow-runner-spec")
    directories << directory unless directories.include?(directory)
    attrs = { name: "Runner spec #{SecureRandom.hex(4)}", kind: kind, local_directory: directory }
    attrs[:repo_full_name] = "acme/widgets" if kind == :jira
    Project.create!(**attrs)
  end

  def workflow(project:, status: :implementing, position: 1, **attrs)
    attrs[:task_description] = "Task #{SecureRandom.hex(4)}" if project.personal?
    project.workflows.create!(status: status, kind: :development, position: position, **attrs)
  end

  it "does nothing without workflows" do
    runner.call
    expect(calls).to be_empty
  end

  it "polls processing workflows before starting waiting ones" do
    waiting = workflow(project: project, position: 1)
    running = workflow(project: project, position: 2, processing: true)

    runner.call

    expect(calls).to eq([ running.id, waiting.id ])
  end

  it "polls mid-run Jira updates and UAT tests" do
    merged = workflow(project: project(kind: :jira), status: :merged, processing: true,
                      jira_ticket: "SPEC-1", branch_name: "b1", github_reviewer: "r")
    uat = workflow(project: project(kind: :jira), status: :uat_testing, processing: true,
                   jira_ticket: "SPEC-2", branch_name: "b2", github_reviewer: "r")

    runner.call

    expect(calls).to contain_exactly(merged.id, uat.id)
  end

  it "starts only one waiting workflow per shared clone" do
    dir = Dir.mktmpdir("active-workflow-runner-clone")
    first = workflow(project: project(directory: dir), position: 1)
    workflow(project: project(directory: "#{dir}/./"), position: 2)
    starting_ids << first.id

    runner.call

    expect(calls).to eq([ first.id ])
  end

  context "with one agent slot" do
    let(:max) { 1 }

    it "stops starting workflows once the slot is taken" do
      first = workflow(project: project, position: 1)
      second = workflow(project: project, position: 2)
      starting_ids.concat([ first.id, second.id ])

      runner.call

      expect(calls).to eq([ first.id ])
    end

    it "counts already-busy clones against capacity" do
      workflow(project: project, position: 1, processing: true)
      waiting = workflow(project: project, position: 2)

      runner.call

      expect(calls).not_to include(waiting.id)
    end
  end

  it "logs a failure and continues with the next workflow" do
    failed = workflow(project: project, position: 1)
    following = workflow(project: project, position: 2)
    failing_ids << failed.id

    runner.call

    expect(calls).to eq([ failed.id, following.id ])
    expect(logger).to have_received(:error).with(/workflow=#{failed.id} RuntimeError: executor failed/)
  end

  it "starts a named non-auto-run runbook only when named" do
    runbook = project.workflows.create!(kind: :runbook, status: :implementing, position: 1, auto_run: false)
    stage = runbook.stages.create!(stage_type: :runbook_step, name: "Deploy", position: 1)
    runbook.update!(current_stage_id: stage.id)

    runner.call
    expect(calls).to be_empty

    runner.call(runbook.id)
    expect(calls).to eq([ runbook.id ])
  end

  it "uses injected query module" do
    queries = class_double(Scheduling::WorkflowQueries, active: [], polling_updates: [])

    described_class.new(queries: queries, executor: executor, logger: logger, max_capacity: 1).call

    expect(calls).to be_empty
  end

  it "defaults the executor to the workflow's current stage" do
    wf = workflow(project: project)
    stage = instance_double(Stage)
    allow(wf).to receive(:current_stage).and_return(stage)
    stage_executor = instance_double(StageExecutor, call: nil)
    allow(StageExecutor).to receive(:new).with(wf, stage).and_return(stage_executor)

    described_class::DEFAULT_EXECUTOR.call(wf)

    expect(stage_executor).to have_received(:call)
  end
end
