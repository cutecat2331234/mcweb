# frozen_string_literal: true

require "sidekiq/web"

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  schedule_file = Rails.root.join("config/sidekiq_cron.yml")
  if File.exist?(schedule_file)
    require "sidekiq/cron/job"

    schedule = YAML.load_file(schedule_file)
    Sidekiq::Cron::Job.load_from_hash!(schedule) if schedule.present?
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
