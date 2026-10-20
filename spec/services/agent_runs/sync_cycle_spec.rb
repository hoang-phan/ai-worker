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

  let(:args) do
    {
      log_prefix: "[Spec] thing=1",
      rescue_errors: [ ArgumentError, AiCli::CommandError ],
      poll: -> { calls << :poll; payload },
      import: ->(p) { calls << [ :import, p ]; "result-of-#{p}" },
      summary: ->(r) { "summary(#{r})" },
      persist: ->(r, s) { calls << [ :persist, r, s ] },
      persist_failure: ->(m) { calls << [ :persist_failure, m ] },
      eligible: -> { eligible },
      idle: -> { idle },
      due: -> { due },
      blockers: -> { blockers },
      start: -> { calls << :start },
      after_import: ->(r) { calls << [ :after_import, r ] },
      after_start: -> { calls << :after_start },
      logger: logger
    }.merge(overrides)
  end

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
        let(:overrides) { { log_message: ->(r, s) { "custom #{r} #{s}" } } }

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

    context "with defaults for the optional gates" do
      let(:args) { super().except(:eligible, :idle, :due, :blockers, :after_start, :after_import) }

      it "starts" do
        expect(outcome.started).to be(true)
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
          let(:overrides) { { step => step == :import ? ->(_p) { raise error } : -> { raise error } } }

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
      let(:overrides) { { poll: -> { raise ArgumentError, "x" * 400 } } }

      it "truncates to 250 characters" do
        outcome
        message = calls.find { |c| c.is_a?(Array) && c.first == :persist_failure }.last
        expect(message.length).to eq(250)
      end
    end

    context "when an import fails after a successful poll" do
      let(:payload) { "p" }
      let(:overrides) { { import: ->(_p) { raise ArgumentError, "bad" } } }

      it "does not report an import" do
        expect(outcome).to have_attributes(imported: false, failed: true)
      end
    end

    context "when the record step fails after import" do
      let(:payload) { "p" }
      let(:overrides) { { persist: ->(_r, _s) { raise ArgumentError, "db" } } }

      it "is reported as failed" do
        expect(outcome.failed).to be(true)
      end
    end

    context "with an unexpected error" do
      let(:overrides) { { poll: -> { raise "surprise" } } }

      it "propagates" do
        expect { outcome }.to raise_error(RuntimeError, "surprise")
      end
    end

    it "lets later records run after a failing one" do
      outcomes = [ -> { raise ArgumentError, "first" }, -> { nil } ].map do |poll|
        described_class.call(**args, poll: poll)
      end
      expect(outcomes.map(&:failed)).to eq([ true, false ])
      expect(outcomes.last.started).to be(true)
    end
  end
end
