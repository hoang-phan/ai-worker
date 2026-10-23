require "rails_helper"

RSpec.describe Stages::AiRunLauncher, type: :service do
  let_tmpdir(:local_directory, "ai-run-launcher-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "LAUNCH-1", branch_name: "launcher", status: :implementing)
  end
  let(:stage) { workflow.stages.create!(stage_type: :implementation, name: "implementation") }
  let(:runner) do
    Class.new do
      class << self
        attr_reader :arguments

        def start(*arguments, **options)
          @arguments = [ arguments, options ]
          4242
        end
      end
    end
  end
  let(:logs) { Class.new { def self.new_path(workflow_id) = "/tmp/workflow-#{workflow_id}.log" } }

  it "starts the runner and records the detached run state and action" do
    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs).call(
      "run this", action: "conflict_resolution_started", mcp_config: "/tmp/mcp.json",
      env: { "TOKEN" => "value" }, disallowed_tools: [ "Bash" ]
    )

    expect(runner.arguments).to eq [
      [ local_directory, "run this" ],
      { log_path: "/tmp/workflow-#{workflow.id}.log", mcp_config: "/tmp/mcp.json", env: { "TOKEN" => "value" }, disallowed_tools: [ "Bash" ], model: nil, effort: nil, provider: nil, allowed_tools: nil }
    ]
    expect(workflow.reload).to have_attributes(
      processing: true, ai_pid: 4242, ai_log_path: "/tmp/workflow-#{workflow.id}.log", ai_log_offset: 0
    )
    expect(workflow.ai_started_at).to be_present
    expect(workflow.ai_provider).to be_nil
    expect(stage.stage_runs.reorder(:id).pluck(:action)).to eq [ "conflict_resolution_started" ]
  end

  it "runs with the stage agent's model and effort" do
    stage.update!(agent: project.agents.create!(name: "billing", description: "Billing", model: "claude-opus-5-5", effort: "high"))

    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs).call("run this")

    expect(runner.arguments.last).to include(model: "claude-opus-5-5", effort: "high")
  end

  it "passes nil model and effort when the agent leaves them blank" do
    stage.update!(agent: project.agents.create!(name: "billing", description: "Billing", model: "", effort: ""))

    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs).call("run this")

    expect(runner.arguments.last).to include(model: nil, effort: nil)
  end

  it "runs the agent's own CLI and tool allow-list and records the provider for the poller" do
    stage.update!(agent: project.agents.create!(name: "billing", description: "Billing", provider: "codex", allowed_tools: [ "Read", "Bash(git log:*)" ]))

    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs).call("run this")

    expect(runner.arguments.last).to include(provider: "codex", allowed_tools: [ "Read", "Bash(git log:*)" ])
    expect(workflow.reload.ai_provider).to eq "codex"
  end

  it "leaves provider and tools unset when the agent has none, as without an agent" do
    stage.update!(agent: project.agents.create!(name: "billing", description: "Billing"))

    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs).call("run this")

    expect(runner.arguments.last).to include(provider: nil, allowed_tools: nil)
    expect(workflow.reload.ai_provider).to be_nil
  end
end
