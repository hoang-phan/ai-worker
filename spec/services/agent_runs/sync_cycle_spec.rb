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

  let(:source_class) do
    Class.new(AgentRuns::CycleSource) do
      attr_accessor :calls, :payload, :eligible, :idle, :due, :blocker_list, :failures, :rescue_errors

      def initialize(calls)
        @calls = calls
        @eligible = @idle = @due = true
        @blocker_list = []
        @failures = {}
        @rescue_errors = [ ArgumentError, AiCli::CommandError ]
      end

      def poll = step(:poll) { payload }
      def import(p) = step(:import, p) { "result-of-#{p}" }
      def summary(r) = "summary(#{r})"
      def persist!(r, s) = step(:persist, r, s) { nil }
      def persist_failure!(m) = calls << [ :persist_failure, m ]
      def eligible? = eligible
      def idle? = idle
      def due? = due
      def blockers = blocker_list
      def start! = step(:start) { nil }
      def after_import(r) = calls << [ :after_import, r ]
      def after_start = calls << :after_start

      private

      def step(name, *args)
        calls << (args.empty? ? name : [ name, *args ])
        raise failures[name] if failures[name]

        yield
      end
    end
  end

  let(:source) do
    source_class.new(calls).tap do |s|
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

  describe "poll / import" do
    context "when nothing finished" do
      it "does not import or record" do
        expect(outcome.imported).to be(false)
        expect(calls).not_to include(a_kind_of(Array).and(start_with(:import)))
        expect(logger).not_to have_received(:info)
      end
    end

    context "when a result finished" do
      let(:payload) { "p" }

      it "imports, logs, persists, then runs the post-import hook in order" do
        expect(outcome.imported).to be(true)
        expect(calls.first(4)).to eq([ :poll, [ :import, "p" ], [ :persist, "result-of-p", "summary(result-of-p)" ], [ :after_import, "result-of-p" ] ])
        expect(logger).to have_received(:info).with("[Spec] thing=1 summary(result-of-p)")
      end

      context "with a custom log message" do
        before { source.define_singleton_method(:log_message) { |r, s| "custom #{r} #{s}" } }

        it "logs it instead of the default" do
          outcome
          expect(logger).to have_received(:info).with("custom result-of-p summary(result-of-p)")
        end
      end

      it "still considers starting after importing" do
        expect(outcome.started).to be(true)
        expect(calls.last(2)).to eq(%i[start after_start])
      end
    end
  end

  describe "starting" do
    it "starts when eligible, idle, due and unblocked" do
      expect(outcome).to have_attributes(started: true, blocked: false, failed: false)
      expect(calls).to eq(%i[poll start after_start])
    end

    {
      "ineligible" => { eligible: false },
      "busy" => { idle: false },
      "not due" => { due: false }
    }.each do |name, attrs|
      context "when #{name}" do
        let(:eligible) { attrs.fetch(:eligible, true) }
        let(:idle) { attrs.fetch(:idle, true) }
        let(:due) { attrs.fetch(:due, true) }

        it "neither starts nor logs a block" do
          expect(outcome).to have_attributes(started: false, blocked: false)
          expect(calls).to eq([ :poll ])
          expect(logger).not_to have_received(:warn)
        end
      end
    end

    context "when blocked" do
      let(:blockers) { [ "dirty tree", "no token" ] }

      it "warns with the reasons and does not start" do
        expect(outcome).to have_attributes(started: false, blocked: true)
        expect(logger).to have_received(:warn).with("[Spec] thing=1 blocked: dirty tree; no token")
        expect(calls).to eq([ :poll ])
      end
    end

    context "with a bare source relying on the CycleSource defaults" do
      let(:bare) do
        Class.new(AgentRuns::CycleSource) do
          attr_reader :started

          def poll = nil
          def start! = @started = true
        end.new
      end
      let(:args) { super().merge(source: bare) }

      it "starts" do
        expect(outcome.started).to be(true)
        expect(bare.started).to be(true)
      end
    end

    context "with a bare CycleSource subclass" do
      let(:bare) do
        Class.new(AgentRuns::CycleSource) do
          def initialize(calls) = @calls = calls
          def poll = "p"
          def import(p) = "r-#{p}"
          def summary(r) = "s(#{r})"
          def persist!(*) = nil
          def persist_failure!(*) = nil
          def start! = @calls << :start
        end.new(calls)
      end
      let(:args) { super().merge(source: bare) }

      it "uses the default hooks and logs the default line" do
        expect(outcome).to have_attributes(imported: true, started: true)
        expect(calls).to eq([ :start ])
        expect(logger).to have_received(:info).with("[Spec] thing=1 s(r-p)")
      end
    end
  end

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

    it "defaults the source's rescue_errors to AiCli::CommandError only" do
      expect(AgentRuns::CycleSource.new.rescue_errors).to eq([ AiCli::CommandError ])
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
      failing = source_class.new([]).tap { |s| s.failures = { poll: ArgumentError.new("first") } }
      outcomes = [ failing, source ].map { |s| described_class.call(**args, source: s) }
      expect(outcomes.map(&:failed)).to eq([ true, false ])
      expect(outcomes.last.started).to be(true)
    end
  end
end
