require "rails_helper"

RSpec.describe Stages::AiRunLauncher, type: :service do
  let_jira_project("ai-run-launcher-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "LAUNCH-1", branch_name: "launcher", status: :implementing)
  end
  let(:stage) { build_stage(workflow, :implementation) }
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
  let(:now) { Time.zone.local(2026, 10, 20, 12, 0) }
  let(:clock) { -> { now } }

  it "starts the runner and records the detached run state and action" do
    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs, clock: clock).call(
      "run this", action: "conflict_resolution_started", mcp_config: "/tmp/mcp.json",
      env: { "TOKEN" => "value" }, disallowed_tools: [ "Bash" ]
    )

    expect(runner.arguments).to eq [
      [ local_directory, "run this" ],
      { log_path: "/tmp/workflow-#{workflow.id}.log", mcp_config: "/tmp/mcp.json", env: { "TOKEN" => "value" }, disallowed_tools: [ "Bash" ], provider: nil }
    ]
    expect(workflow.reload).to have_attributes(
      processing: true, ai_pid: 4242, ai_log_path: "/tmp/workflow-#{workflow.id}.log",
      ai_started_at: now, ai_log_offset: 0
    )
    expect(workflow.ai_provider).to be_nil
    expect(stage_actions(stage)).to eq [ "conflict_resolution_started" ]
  end
end
