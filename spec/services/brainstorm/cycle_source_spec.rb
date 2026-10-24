require "rails_helper"

RSpec.describe Brainstorm::CycleSource do
  let(:record) { double("project", update: true) }
  let(:planner) do
    instance_double(Brainstorm::Planner, poll: nil, running?: false, wait_reason: nil, blockers: [ "no goal" ],
                    start: nil, record_start!: nil)
  end
  let(:source) { described_class.new(record, planner: planner) }

  it "delegates poll, import, blockers and start!" do
    allow(planner).to receive(:poll).and_return([ 1 ])
    allow(planner).to receive(:import).with([ 1 ]).and_return(:imported)

    expect(source.poll).to eq([ 1 ])
    expect(source.import([ 1 ])).to eq(:imported)
    expect(source.blockers).to eq([ "no goal" ])
    source.start!
    expect(planner).to have_received(:start)
  end

  it "records the start on the planner after_start" do
    source.after_start
    expect(planner).to have_received(:record_start!)
  end

  it "persists summaries and failures to brainstorm_last_result" do
    source.persist!(nil, "sum")
    source.persist_failure!("failed: x")
    expect(record).to have_received(:update).with(brainstorm_last_result: "sum")
    expect(record).to have_received(:update).with(brainstorm_last_result: "failed: x")
  end

  it "rescues its FetchError and AiCli::CommandError" do
    expect(source.rescue_errors).to equal(described_class::RESCUE_ERRORS)
    expect(described_class::RESCUE_ERRORS).to eq([ Brainstorm::FetchError, AiCli::CommandError ]).and be_frozen
  end

  it "is idle when not running and due when the planner has no wait reason" do
    expect(source.idle?).to be(true)
    expect(source.due?).to be(true)
    allow(planner).to receive_messages(running?: true, wait_reason: "pending workflows")
    expect(source.idle?).to be(false)
    expect(source.due?).to be(false)
  end
end
