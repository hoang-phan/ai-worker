require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::ActiveWorkflowRunner do
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

  def project(directory: nil, kind: :personal)
    directory ||= make_tmpdir("active-workflow-runner-spec")
    kind == :jira ? build_jira_project(local_directory: directory) : build_personal_project(local_directory: directory)
  end

  def workflow(project:, status: :implementing, position: 1, **attrs)
    builder = project.jira? ? :build_jira_workflow : :build_task_workflow
    public_send(builder, project, status: status, kind: :development, position: position, **attrs)
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
    dir = make_tmpdir("active-workflow-runner-clone")
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
    runbook = build_runbook_workflow(project, status: :implementing, position: 1, auto_run: false)
    stage = build_runbook_stage(runbook, name: "Deploy", position: 1)
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

  it "builds an injected stage executor for the workflow's current stage" do
    wf = workflow(project: project)
    stage = instance_double(Stage)
    allow(wf).to receive(:current_stage).and_return(stage)
    executions = []
    executor_class = Struct.new(:workflow, :stage) do
      define_method(:call) { executions << [ workflow, stage ] }
    end

    described_class.stage_executor(executor_class: executor_class).call(wf)

    expect(executions).to eq([ [ wf, stage ] ])
  end

  it "does not build an injected stage executor without a current stage" do
    wf = workflow(project: project)
    allow(wf).to receive(:current_stage).and_return(nil)
    executions = []
    executor_class = Struct.new(:workflow, :stage) do
      define_method(:call) { executions << [ workflow, stage ] }
    end

    described_class.stage_executor(executor_class: executor_class).call(wf)

    expect(executions).to be_empty
  end
end
