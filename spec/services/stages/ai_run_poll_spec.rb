require "rails_helper"

RSpec.describe Stages::AiRunPoll, type: :service do
  let_jira_project("ai-run-poll-spec")
  let(:workflow) do
    build_jira_workflow(
      project, jira_ticket: "POLL-1", branch_name: "poll", status: :implementing,
      **running_ai_run(ai_log_offset: 4, ai_provider: "codex")
    )
  end
  let(:stage) { workflow.stages.create!(stage_type: :task) }
  let(:poller_class) { class_double(AiCli::RunPoller) }
  let(:poller) { instance_double(AiCli::RunPoller, log_offset: 4) }
  let(:stale_after) { 3.hours }
  subject(:ai_run_poll) do
    described_class.new(workflow: workflow, stage: stage, poller_class: poller_class, stale_after: stale_after)
  end

  it "returns nil while the run is still going" do
    allow(poller_class).to receive(:new).and_return(poller)
    allow(poller).to receive(:call).and_return([ :running, nil ])

    expect(ai_run_poll.call).to be_nil
  end

  it "returns a finished run's output" do
    allow(poller_class).to receive(:new).and_return(poller)
    allow(poller).to receive(:call).and_return([ :finished, "all done" ])

    expect(ai_run_poll.call).to eq "all done"
  end

  it "passes the workflow run state and stale timeout to its poller" do
    expect(poller_class).to receive(:new).with(
      pid: 123, log_path: "/tmp/x.log", log_offset: 4, started_at: workflow.ai_started_at,
      provider: "codex", log_tag: "workflow=#{workflow.id} stage=#{stage.id}", stale_after: stale_after
    ).and_return(poller)
    allow(poller).to receive(:call).and_return([ :running, nil ])

    ai_run_poll.call
  end

  it "persists the changed log offset" do
    allow(poller_class).to receive(:new).and_return(poller)
    allow(poller).to receive(:call).and_return([ :running, nil ])
    allow(poller).to receive(:log_offset).and_return(9)

    ai_run_poll.call

    expect(workflow.reload.ai_log_offset).to eq 9
  end

  it "does not write the log offset when it is unchanged" do
    allow(poller_class).to receive(:new).and_return(poller)
    allow(poller).to receive(:call).and_return([ :running, nil ])
    expect(workflow).not_to receive(:update_column)

    ai_run_poll.call
  end

  it "persists a changed log offset when the poller raises" do
    allow(poller_class).to receive(:new).and_return(poller)
    allow(poller).to receive(:log_offset).and_return(9)
    allow(poller).to receive(:call).and_raise(AiCli::CommandError, "timed out")

    expect { ai_run_poll.call }.to raise_error(AiCli::CommandError, "timed out")
    expect(workflow.reload.ai_log_offset).to eq 9
  end
end
