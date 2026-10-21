require "rails_helper"

RSpec.describe AgentRuns::ManualStart do
  let(:errors) { [ ArgumentError ] }
  let(:started) { [] }

  def run(**overrides)
    described_class.call(
      blockers: -> { [] }, start: -> { started << :start; true }, rescue_errors: errors, **overrides
    )
  end

  it "is blocked with the joined blockers and does not start" do
    result = run(blockers: -> { %w[a b] })
    expect([ result.status, result.detail ]).to eq([ :blocked, "a; b" ])
    expect(started).to be_empty
  end

  it "is skipped with the skip message and does not start" do
    result = run(skip_reason: -> { "pending" })
    expect([ result.status, result.detail ]).to eq([ :skipped, "pending" ])
    expect(started).to be_empty
  end

  it "is started when start returns true" do
    expect(run.status).to eq(:started)
  end

  it "is already_running when start returns false" do
    expect(run(start: -> { false }).status).to eq(:already_running)
  end

  it "is failed with the message for a listed error" do
    result = run(start: -> { raise ArgumentError, "boom" })
    expect([ result.status, result.detail ]).to eq([ :failed, "boom" ])
  end

  it "lets unlisted errors propagate" do
    expect { run(start: -> { raise KeyError, "nope" }) }.to raise_error(KeyError)
  end

  it "runs after_start only on a successful start" do
    calls = []
    run(after_start: -> { calls << :ok })
    run(start: -> { false }, after_start: -> { calls << :already })
    run(blockers: -> { [ "x" ] }, after_start: -> { calls << :blocked })
    run(skip_reason: -> { "s" }, after_start: -> { calls << :skipped })
    expect(calls).to eq([ :ok ])
  end
end
