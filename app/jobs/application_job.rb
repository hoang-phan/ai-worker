class ApplicationJob < ActiveJob::Base
  # Sidekiq-cron previously persisted some scheduled Active Jobs as raw Sidekiq
  # workers. Sidekiq 8 sets these fields before calling #perform, so keep the
  # old in-flight retries runnable while the schedule enqueues the proper
  # Active Job wrapper.
  attr_accessor :jid, :_context

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
