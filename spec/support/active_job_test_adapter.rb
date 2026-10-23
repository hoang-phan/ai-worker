# Swaps ActiveJob's queue adapter to :test for examples tagged `active_job_test_adapter: true`, restoring it afterwards.
RSpec.configure do |config|
  config.around(:each, active_job_test_adapter: true) do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end
end
