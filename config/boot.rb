ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
require_relative "../lib/mcweb/local_config"

if Mcweb::LocalConfig.exist?
  db = Mcweb::LocalConfig.load["database"]
  if db.is_a?(Hash) && db.values.any? { |value| !value.nil? && value != "" }
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
