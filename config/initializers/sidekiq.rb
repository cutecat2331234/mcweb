# frozen_string_literal: true

require "sidekiq/web"
require "sidekiq/cron"
require_relative "../../lib/mcweb/sidekiq_cron_schedule"

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Mcweb::SidekiqCronSchedule.configure_scheduler!(
  configuration: Sidekiq::Cron.configuration
)

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  schedule_file = Rails.root.join("config/sidekiq_cron.yml")
  Mcweb::SidekiqCronSchedule.register!(schedule_path: schedule_file) do |schedule|
    require "sidekiq/cron/job"
    Sidekiq::Cron::Job.load_from_hash!(schedule) if schedule.present?
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
