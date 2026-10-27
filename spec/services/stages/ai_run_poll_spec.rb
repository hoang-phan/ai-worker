require "rails_helper"

RSpec.describe Stages::AiRunPoll, type: :service do
  let_jira_project("ai-run-poll-spec")
  let_tmpdir(:dir, "ai-run-poll-spec")
  let(:log_path) { File.join(dir, "run.log") }
  let(:log_text) { "agent output\n" }
  let(:workflow) do
    build_jira_workflow(
      project, jira_ticket: "POLL-1", branch_name: "poll", status: :implementing,
      **running_ai_run(ai_log_path: log_path, ai_log_offset: initial_log_offset, ai_provider: "codex")
    )
  end
  let(:stage) { workflow.stages.create!(stage_type: :task) }
  let(:poller_class) { AiCli::RunPoller }
  let(:stale_after) { 3.hours }
  let(:initial_log_offset) { 0 }
  let(:poll_result) { :running }
  let(:runner) { FakeRunner.new(poll_result) }

  class FakeRunner
    attr_writer :result

    def initialize(result)
      @result = result
    end

    def poll(_pid)
      @result
    end

    def agent
      "fake-agent"
    end
  end

  subject(:ai_run_poll) do
    described_class.new(
      workflow: workflow, stage: stage, poller_class: poller_class, stale_after: stale_after, poller_runner: runner
    )
  end

  before { File.write(log_path, log_text) }

  it "returns nil while the run is still going" do
    expect(ai_run_poll.call).to be_nil
  end

  it "returns a finished run's real log output" do
    runner.result = [ :completed, status(true) ]

    expect(ai_run_poll.call).to eq log_text
  end

  it "persists the log offset after reading new log bytes" do
    ai_run_poll.call

    expect(workflow.reload.ai_log_offset).to eq log_text.bytesize
  end

  it "does not write the log offset when the log is unchanged" do
    workflow.update_column(:ai_log_offset, log_text.bytesize)
    expect(workflow).not_to receive(:update_column)

    ai_run_poll.call
  end

  it "persists a changed log offset when the poller raises" do
    runner.result = [ :completed, status(false) ]

    expect { ai_run_poll.call }.to raise_error(AiCli::CommandError, "codex failed (pid=123): #{log_text}")
    expect(workflow.reload.ai_log_offset).to eq log_text.bytesize
  end

  it "uses the real CI poller" do
    ci_runner = FakeRunner.new([ :completed, status(false, exitstatus: 2) ])
    ci_poll = described_class.new(
      workflow: workflow, stage: stage, poller_class: Ci::CheckPoller, stale_after: stale_after, poller_runner: ci_runner
    )

    expect(ci_poll.call).to eq 2
  end

  def status(success, exitstatus: nil)
    instance_double(Process::Status, success?: success, exitstatus: exitstatus)
  end
end
