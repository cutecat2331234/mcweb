# frozen_string_literal: true

expected_suffix = "_e2e"
database_name = ActiveRecord::Base.connection_db_config.database.to_s
unless Rails.env.test? && database_name.end_with?(expected_suffix)
  abort(
    "Refusing system-E2E seed outside an isolated test database ending " \
    "#{expected_suffix.inspect}; current=#{database_name.inspect}"
  )
end

owner = User.find_or_initialize_by(email: "e2e-owner@mcweb.test")
owner.assign_attributes(
  username: "e2e_owner",
  password: "E2e-password-123!",
  password_confirmation: "E2e-password-123!",
  email_verified: true,
  email_verified_at: Time.current,
  developer_mode_email_verified: false,
  locale: "en",
  time_zone: "Asia/Shanghai",
  status: "active",
  account_type: "owner",
  totp_enabled: false,
  totp_secret: nil,
  recovery_codes: []
)
owner.save!
InstallationLock.lock!(user: owner)

# Each Playwright launch must begin below the production login thresholds while
# keeping the production limiter enabled for the browser flow itself.
RateLimitCounter.delete_all

if ActiveRecord::Base.connection.data_source_exists?("operations_metric_buckets")
  Operations::MetricBucket.delete_all
end
if ActiveRecord::Base.connection.data_source_exists?("operations_worker_heartbeats")
  Operations::WorkerHeartbeat.delete_all
end

puts "System E2E owner ready in #{database_name}."
