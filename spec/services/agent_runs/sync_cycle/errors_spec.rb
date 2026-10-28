require "rails_helper"

RSpec.describe AgentRuns::SyncCycle do
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, warn: nil, error: nil) }
  let(:calls) { [] }
  let(:payload) { nil }
  let(:eligible) { true }
  let(:idle) { true }
  let(:due) { true }
  let(:blockers) { [] }

  let(:overrides) { {} }

  let(:source) do
    FakeCycleSource.new(calls).tap do |s|
      s.payload = payload
      s.eligible = eligible
      s.idle = idle
      s.due = due
      s.blocker_list = blockers
      overrides.each { |name, value| s.public_send("#{name}=", value) }
    end
  end

  let(:args) { { source: source, log_prefix: "[Spec] thing=1", logger: logger } }

  subject(:outcome) { described_class.call(**args) }

  describe "expected errors" do
    {
      "a poll error" => :poll,
      "an import error" => :import,
      "a start error" => :start
    }.each do |name, step|
      [ ArgumentError.new("boom"), AiCli::CommandError.new("cli boom") ].each do |error|
        context "when #{name} raises #{error.class}" do
          let(:payload) { "p" }
          let(:overrides) { { failures: { step => error } } }

          it "logs, records a truncated failure and returns failed without raising" do
            expect(outcome.failed).to be(true)
            expect(outcome.started).to be(false)
            expect(logger).to have_received(:error).with("[Spec] thing=1 #{error.message}")
            expect(calls).to include([ :persist_failure, "failed: #{error.message}" ])
          end
        end
      end
    end

    context "when the persisted error message is long" do
      let(:overrides) { { failures: { poll: ArgumentError.new("x" * 400) } } }

      it "truncates to 250 characters" do
        outcome
        message = calls.find { |c| c.is_a?(Array) && c.first == :persist_failure }.last
        expect(message.length).to eq(250)
      end
    end

    context "when an import fails after a successful poll" do
      let(:payload) { "p" }
      let(:overrides) { { failures: { import: ArgumentError.new("bad") } } }

      it "does not report an import" do
        expect(outcome).to have_attributes(imported: false, failed: true)
      end
    end

    context "when the record step fails after import" do
      let(:payload) { "p" }
      let(:overrides) { { failures: { persist: ArgumentError.new("db") } } }

      it "is reported as failed" do
        expect(outcome.failed).to be(true)
      end
    end

    context "with an unexpected error" do
      let(:overrides) { { failures: { poll: RuntimeError.new("surprise") } } }

      it "propagates" do
        expect { outcome }.to raise_error(RuntimeError, "surprise")
      end
    end

    context "without a rescue_errors: keyword" do
      let(:overrides) { { failures: { poll: ArgumentError.new("boom") }, rescue_errors: [ AiCli::CommandError ] } }

      it "rescues only the source's errors" do
        expect { outcome }.to raise_error(ArgumentError, "boom")
      end
    end

    context "with an explicit rescue_errors: keyword" do
      let(:overrides) { { failures: { poll: ArgumentError.new("boom") } } }

      it "uses it instead of the source's list" do
        expect { described_class.call(**args, rescue_errors: [ AiCli::CommandError ]) }.to raise_error(ArgumentError, "boom")
        expect(described_class.call(**args, rescue_errors: [ ArgumentError ]).failed).to be(true)
      end
    end

    it "lets later records run after a failing one" do
      failing = FakeCycleSource.new([]).tap { |s| s.failures = { poll: ArgumentError.new("first") } }
      outcomes = [ failing, source ].map { |s| described_class.call(**args, source: s) }
      expect(outcomes.map(&:failed)).to eq([ true, false ])
      expect(outcomes.last.started).to be(true)
    end
  end
end
