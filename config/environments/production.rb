require "active_support/core_ext/integer/time"
require_relative "../developer_mode_runtime"
require_relative "../../lib/mcweb/production_environment"

Rails.application.configure do
  developer_mode_settings = Mcweb::DeveloperMode.settings
  Mcweb::DeveloperMode.require_production_confirmation!(
    settings: developer_mode_settings,
    environment: ENV
  )
  production_requirements =
    Mcweb::DeveloperModeRuntime.production_requirements(developer_mode_settings)
  production_environment = Mcweb::ProductionEnvironment.load_selected!(
    ENV,
    **production_requirements
  )

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Serve static files from public/ (required when nginx only reverse-proxies to Puma).
  config.public_file_server.enabled = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Production uploads must use the private S3-compatible service declared in
  # config/storage.yml. Local container or release disks are not durable.
  config.active_storage.service = production_environment.storage_service || :local

  # McWeb's supported production topology terminates TLS at a trusted reverse
  # proxy. The app still redirects accidental HTTP requests and emits HSTS.
  if production_requirements.fetch(:trusted_proxy_policy)
    config.assume_ssl = true
    config.force_ssl = true
    config.ssl_options = {
      hsts: {
        expires: 1.year,
        subdomains: true,
        preload: false
      },
      redirect: { status: 308 }
    }
    config.action_dispatch.trusted_proxies = production_environment.trusted_proxies
  end


  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :sidekiq

  if production_requirements.fetch(:mail)
    public_url_options = production_environment.default_url_options
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.default_options = { from: production_environment.mail_from }
    config.action_mailer.default_url_options = public_url_options
    config.action_mailer.smtp_settings = production_environment.smtp_settings
    Rails.application.routes.default_url_options = public_url_options
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Exact public hosts only. Health checks use the same Host policy.
  if production_requirements.fetch(:host_authorization)
    config.hosts = production_environment.allowed_hosts
  end

  Mcweb::DeveloperModeRuntime.apply!(
    config,
    settings: developer_mode_settings
  )

  if developer_mode_settings.enabled?
    profile = developer_mode_settings.profile
    config.after_initialize do
      Rails.logger.fatal(
        "[mcweb] CRITICAL: RAILS_ENV=production is running with " \
        "Developer Mode profile=#{profile}. Security checks and production " \
        "optimizations may be disabled according to config/local.yml."
      )
    end
  end
end
