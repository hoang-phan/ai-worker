require "rails_helper"

RSpec.describe Brainstorm::CycleSource do
  let(:project) { build_personal_project(local_directory: make_tmpdir("cycle-source").to_s, brainstorm_goal: "improve things") }
  let(:planner) { instance_double(Brainstorm::Planner, poll: nil, running?: false, start: nil) }
  let(:clock) { -> { Time.current } }
  let(:source) { described_class.new(project, planner: planner, clock: clock) }

  def add_workflow(**attrs)
    build_task_workflow(project, **{ task_description: "do it" }.merge(attrs))
  end

  it "delegates poll, import and start! to the planner" do
    allow(planner).to receive(:poll).and_return([ 1 ])
    allow(planner).to receive(:import).with([ 1 ]).and_return(:imported)

    expect(source.poll).to eq([ 1 ])
    expect(source.import([ 1 ])).to eq(:imported)
    source.start!
    expect(planner).to have_received(:start)
  end

  describe "#blockers" do
    it "reports RunBlockers messages for personal kind, goal and local directory" do
      project.update_columns(brainstorm_goal: nil, local_directory: "/no/such/brainstorm-dir")

      expect(source.blockers).to eq([ "no goal set", "local directory does not exist" ])
    end
  end

  describe "#skip_reason" do
    it "is nil when nothing is pending" do
      expect(source.skip_reason).to be_nil
      expect(source.due?).to be(true)
    end

    it "names the number of pending development workflows" do
      2.times { add_workflow(status: :pending) }

      expect(source.skip_reason).to eq("2 workflow(s) still pending; start or delete them first.")
      expect(source.due?).to be(false)
    end

    it "ignores implementing and runbook workflows" do
      add_workflow(status: :implementing)
      add_workflow(kind: :runbook, status: :pending)

      expect(source.skip_reason).to be_nil
    end
  end

  describe "#after_start" do
    it "stamps brainstorm_last_run_at with the clock time" do
      at = Time.zone.local(2026, 1, 2, 3, 4, 5)
      source = described_class.new(project, planner: planner, clock: -> { at })

      source.after_start

      expect(project.reload.brainstorm_last_run_at).to eq(at)
    end
  end

  it "persists summaries and failures to brainstorm_last_result" do
    source.persist!(nil, "sum")
    expect(project.reload.brainstorm_last_result).to eq("sum")
    source.persist_failure!("failed: x")
    expect(project.reload.brainstorm_last_result).to eq("failed: x")
  end

  it "rescues its FetchError and AiCli::CommandError" do
    expect(source.rescue_errors).to equal(described_class::RESCUE_ERRORS)
    expect(described_class::RESCUE_ERRORS).to eq([ Brainstorm::FetchError, AiCli::CommandError ]).and be_frozen
  end

  it "is idle when the planner is not running" do
    expect(source.idle?).to be(true)
    allow(planner).to receive(:running?).and_return(true)
    expect(source.idle?).to be(false)
  end
end
