require "rails_helper"

RSpec.describe "the Sidekiq cron schedule" do
  let(:schedule) { YAML.load_file(Rails.root.join("config/schedule.yml")) }

  it "enqueues every scheduled Rails job through Active Job" do
    expect(schedule.values).to all(include("active_job" => true))
  end

  it "uses a parseable cron with exactly five time fields for every entry" do
    schedule.each do |name, entry|
      cron = entry.fetch("cron")
      fields = cron.split
      fields.pop if TZInfo::Timezone.all_identifiers.include?(fields.last)

      expect(Fugit::Cron.parse(cron)).not_to be_nil, "#{name}: cron #{cron.inspect} does not parse"
      expect(fields.size).to eq(5), "#{name}: cron #{cron.inspect} has #{fields.size} time fields, expected 5"
    end
  end

  it "builds an Active Job wrapper when the job class is not loaded yet" do
    job = Sidekiq::Cron::Job.new(
      schedule.fetch("slack_ping").merge("class" => "NotLoadedYetJob", "fetch_missing_args" => false)
    )

    # enqueue! also persists last-enqueue metadata to Redis; assert the public message builder instead.
    expect(job.active_job_message).to include(
      "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped" => "NotLoadedYetJob"
    )
  end
end
