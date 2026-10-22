require "rails_helper"

RSpec.describe Stages::AiRunLauncher, type: :service do
  let(:local_directory) { Dir.mktmpdir("ai-run-launcher-spec") }
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

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "starts the runner and records the detached run state and action" do
    described_class.new(workflow: workflow, stage: stage, project: project, runner: runner, logs: logs).call(
      "run this", action: "conflict_resolution_started", mcp_config: "/tmp/mcp.json",
      env: { "TOKEN" => "value" }, disallowed_tools: [ "Bash" ]
    )

    expect(runner.arguments).to eq [
      [ local_directory, "run this" ],
      { log_path: "/tmp/workflow-#{workflow.id}.log", mcp_config: "/tmp/mcp.json", env: { "TOKEN" => "value" }, disallowed_tools: [ "Bash" ] }
    ]
    expect(workflow.reload).to have_attributes(
      processing: true, ai_pid: 4242, ai_log_path: "/tmp/workflow-#{workflow.id}.log", ai_log_offset: 0
    )
    expect(workflow.ai_started_at).to be_present
    expect(stage.stage_runs.reorder(:id).pluck(:action)).to eq [ "conflict_resolution_started" ]
  end
end
