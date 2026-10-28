require "rails_helper"

RSpec.describe AgentRuns::ManualStart do
  let(:errors) { [ ArgumentError ] }
  let(:started) { [] }

  def run(**overrides)
    described_class.new(
      blockers: -> { [] }, start: -> { started << :start; true }, rescue_errors: errors, **overrides
    ).call
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

  describe ".for" do
    # Spec-local CycleSource so ManualStart.for is covered without constructor
    # stubs of a production source (constructor_stub_ratchet).
    class SpecCycleSource < AgentRuns::CycleSource
      RESCUE_ERRORS = [ ArgumentError ].freeze

      def initialize(blockers: [], skip_reason: nil, start_result: true, raise_on_start: nil)
        @blockers = blockers
        @skip_reason = skip_reason
        @start_result = start_result
        @raise_on_start = raise_on_start
        @started = false
        @after_started = false
      end

      attr_reader :started, :after_started

      def blockers = @blockers
      def skip_reason = @skip_reason
      def rescue_errors = RESCUE_ERRORS

      def start!
        raise @raise_on_start if @raise_on_start

        @started = true
        @start_result
      end

      def after_start
        @after_started = true
      end
    end

    it "wires blockers, skip_reason, start!, after_start and rescue_errors from the source" do
      source = SpecCycleSource.new
      result = described_class.for(source).call

      expect(result.status).to eq(:started)
      expect(source.started).to be(true)
      expect(source.after_started).to be(true)
    end

    it "is blocked, skipped, already_running or failed from the source hooks" do
      blocked = described_class.for(SpecCycleSource.new(blockers: %w[a b])).call
      expect([ blocked.status, blocked.detail ]).to eq([ :blocked, "a; b" ])

      skipped = described_class.for(SpecCycleSource.new(skip_reason: "wait")).call
      expect([ skipped.status, skipped.detail ]).to eq([ :skipped, "wait" ])

      running = described_class.for(SpecCycleSource.new(start_result: false)).call
      expect(running.status).to eq(:already_running)

      failed = described_class.for(SpecCycleSource.new(raise_on_start: ArgumentError.new("boom"))).call
      expect([ failed.status, failed.detail ]).to eq([ :failed, "boom" ])
    end
  end
end
