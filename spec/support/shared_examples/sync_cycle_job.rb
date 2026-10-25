# Shared coverage for jobs that enumerate records and run an agent sync cycle.
# Include from a job spec with these lets:
#
#   source_class       - the cycle source class constructed for each record
#   eligible_records   - persisted records the job should run
#   ineligible_records - persisted records the job should skip
#   log_prefix_for     - lambda returning the exact prefix for one record
#   error_class        - expected error class raised by a source poll
#   failure_observer   - lambda reading or writing the persisted failure
#
# Job-specific record selection belongs in the including spec.
RSpec.shared_examples "an agent sync-cycle job" do
  it "runs one sync cycle per eligible record and skips ineligible records" do
    ineligible_records
    sources = eligible_records.to_h { |record| [ record, instance_double(source_class) ] }

    eligible_records.each do |record|
      expect(source_class).to receive(:new).with(record).ordered.and_return(sources.fetch(record))
      expect(AgentRuns::SyncCycle).to receive(:call).with(
        source: sources.fetch(record),
        log_prefix: log_prefix_for.call(record)
      ).ordered
    end

    described_class.perform_now
  end

  it "persists an expected error and continues to the next record" do
    failing_record, next_record = eligible_records.first(2)
    failing_source = instance_double(source_class, poll: nil, persist_failure!: nil, rescue_errors: source_class::RESCUE_ERRORS)
    next_source = instance_double(source_class, poll: nil, rescue_errors: source_class::RESCUE_ERRORS, eligible?: true, idle?: true, due?: true, blockers: [], start!: nil, after_start: nil)

    allow(failing_source).to receive(:poll).and_raise(error_class, "source unavailable")
    allow(failing_source).to receive(:persist_failure!) { |message| failure_observer.call(failing_record, message) }
    allow(source_class).to receive(:new) { |record, **| record == failing_record ? failing_source : next_source }
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(failure_observer.call(failing_record)).to eq("failed: source unavailable")
    expect(next_source).to have_received(:start!)
  end
end
