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

      context "with a log detail" do
        before { source.define_singleton_method(:log_detail) { |r| "detail #{r}" } }

        it "appends it to the default line" do
          outcome
          expect(logger).to have_received(:info).with("[Spec] thing=1 summary(result-of-p) detail result-of-p")
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
end
