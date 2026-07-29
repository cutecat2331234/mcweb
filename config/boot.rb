ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Developer Mode settings are cached below, before Rails loads
# config/environments/test.rb. A local development configuration must never
# make the normal test suite use fake integrations or relaxed security.
if ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
  ENV["MCWEB_DEVELOPER_MODE"] = "0"
end

require "bundler/setup" # Set up gems listed in the Gemfile.
require_relative "../lib/mcweb/local_config"
require_relative "../lib/mcweb/developer_mode"

# Developer Mode can affect boot-time runtime choices, so validate its strict
# local configuration before Bootsnap or the Rails environment is initialized.
Mcweb::DeveloperMode.settings

require "bootsnap/setup" # Speed up boot time by caching expensive operations.

if Mcweb::LocalConfig.exist?
  db = Mcweb::LocalConfig.load["database"]
  if ENV.fetch("RAILS_ENV", "development") != "production" &&
      db.is_a?(Hash) &&
      db.values.any? { |value| !value.nil? && value != "" }
    ENV.delete("DATABASE_URL")
  end

  if ENV["REDIS_URL"].to_s.strip.empty?
    redis_url = Mcweb::LocalConfig.load["redis_url"]
    ENV["REDIS_URL"] = redis_url.to_s if redis_url.to_s.strip != ""
  end

  if ENV["JOB_CONCURRENCY"].to_s.strip.empty?
    job_concurrency = Mcweb::LocalConfig.load["job_concurrency"]
    ENV["JOB_CONCURRENCY"] = job_concurrency.to_s if job_concurrency.to_s.strip != ""
  end
end
