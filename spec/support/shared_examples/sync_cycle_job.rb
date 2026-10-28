# Shared coverage for jobs that enumerate records and run an agent sync cycle.
# Include from a job spec with these lets:
#
#   source_class       - the cycle source class used for verified doubles and rescue errors
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
    factory_records = []
    source_factory = ->(record) { factory_records << record; sources.fetch(record) }
    cycle_calls = []
    cycle = ->(**kwargs) { cycle_calls << kwargs }

    described_class.perform_now(source_factory: source_factory, cycle: cycle)

    expect(factory_records).to eq(eligible_records)
    expect(cycle_calls).to match(
      eligible_records.map do |record|
        hash_including(source: sources.fetch(record), log_prefix: log_prefix_for.call(record))
      end
    )
  end

  it "persists an expected error and continues to the next record" do
    failing_record, next_record = eligible_records.first(2)
    failing_source = instance_double(source_class, poll: nil, persist_failure!: nil, rescue_errors: source_class::RESCUE_ERRORS)
    next_source = instance_double(source_class, poll: nil, rescue_errors: source_class::RESCUE_ERRORS, eligible?: true, idle?: true, due?: true, blockers: [], start!: nil, after_start: nil)
    factory_records = []
    source_factory = lambda do |record|
      factory_records << record
      record == failing_record ? failing_source : next_source
    end

    allow(failing_source).to receive(:poll).and_raise(error_class, "source unavailable")
    allow(failing_source).to receive(:persist_failure!) { |message| failure_observer.call(failing_record, message) }

    described_class.perform_now(source_factory: source_factory, logger: ActiveSupport::Logger.new(StringIO.new))

    expect(failure_observer.call(failing_record)).to eq("failed: source unavailable")
    expect(factory_records).to eq([ failing_record, next_record ])
    expect(next_source).to have_received(:start!)
  end
end
