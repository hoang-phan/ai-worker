require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::CurrentStageExecutor do
  def project
    build_personal_project(local_directory: make_tmpdir("current-stage-executor-spec"))
  end

  def workflow
    build_task_workflow(project, status: :implementing, kind: :development, position: 1)
  end

  it "builds an injected stage executor for the workflow's current stage" do
    wf = workflow
    stage = instance_double(Stage)
    allow(wf).to receive(:current_stage).and_return(stage)
    executions = []
    executor_class = Struct.new(:workflow, :stage) do
      define_method(:call) { executions << [ workflow, stage ] }
    end

    described_class.new(executor_class: executor_class).call(wf)

    expect(executions).to eq([ [ wf, stage ] ])
  end

  it "does not build an injected stage executor without a current stage" do
    wf = workflow
    allow(wf).to receive(:current_stage).and_return(nil)
    executions = []
    executor_class = Struct.new(:workflow, :stage) do
      define_method(:call) { executions << [ workflow, stage ] }
    end

    described_class.new(executor_class: executor_class).call(wf)

    expect(executions).to be_empty
  end
end
