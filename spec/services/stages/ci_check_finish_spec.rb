require "rails_helper"

RSpec.describe Stages::CiCheckFinish, type: :service do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) do
    build_ci_workflow(project, status: :ci_verifying, **running_ai_run)
  end
  let(:stage) { workflow.stages.find_by!(stage_type: :ci_check) }

  def actions(stage) = stage.stage_runs.reorder(:id).pluck(:action)

  def finish(exit_status) = described_class.new(workflow: workflow, stage: stage).call(exit_status)

  it "keeps the log path and exit status, and hands over to the verify stage even when the check failed" do
    log = Tempfile.new("ci").tap { |f| f.write("boom\n"); f.flush }
    workflow.update!(ai_log_path: log.path, status: :ci_checking)

    finish(1)

    expect(workflow.reload).to have_attributes(status: "ci_verifying", ci_output_path: log.path, ci_exit_status: 1)
    expect(stage.stage_runs.last.output).to include("exit status 1", "boom")
    expect(actions(stage)).to eq %w[ci_check_completed]
  end

  it "clears the AI run fields" do
    workflow.update!(status: :ci_checking)

    finish(0)

    expect(workflow.reload).to have_attributes(Workflow::AI_RUN_RESET)
  end

  it "still hands over with an empty tail when the log file is missing" do
    path = File.join(Dir.tmpdir, "missing-ci-#{SecureRandom.hex(4)}.log")
    workflow.update!(ai_log_path: path, status: :ci_checking)

    finish(2)

    expect(workflow.reload).to have_attributes(status: "ci_verifying", ci_output_path: path, ci_exit_status: 2)
    expect(stage.stage_runs.last.output).to eq "exit status 2\n"
  end

  it "still hands over with an empty tail when the log file is empty" do
    log = Tempfile.new("ci")
    workflow.update!(ai_log_path: log.path, status: :ci_checking)

    finish(0)

    expect(workflow.reload).to have_attributes(status: "ci_verifying", ci_output_path: log.path, ci_exit_status: 0)
    expect(stage.stage_runs.last.output).to eq "exit status 0\n"
  end

  it "only keeps the last bytes of a long log" do
    log = Tempfile.new("ci").tap { |f| f.write("HEAD" + "x" * 5000 + "TAIL"); f.flush }
    workflow.update!(ai_log_path: log.path, status: :ci_checking)

    finish(1)

    output = stage.stage_runs.last.output
    expect(output).to include("TAIL")
    expect(output).not_to include("HEAD")
  end
end
