require "rails_helper"

RSpec.describe "the Sidekiq cron schedule" do
  let(:schedule) { YAML.load_file(Rails.root.join("config/schedule.yml")) }

  it "enqueues every scheduled Rails job through Active Job" do
    expect(schedule.values).to all(include("active_job" => true))
  end

  it "builds an Active Job wrapper when the job class is not loaded yet" do
    job = Sidekiq::Cron::Job.new(
      schedule.fetch("slack_ping").merge("class" => "NotLoadedYetJob", "fetch_missing_args" => false)
    )

    expect(job.send(:active_job_message)).to include(
      "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped" => "NotLoadedYetJob"
    )
  end
end
