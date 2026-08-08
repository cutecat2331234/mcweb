require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "rails/test_unit/railtie"
require_relative "../lib/mcweb/request_performance_middleware"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Mcweb
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    secret_key_base = ENV["SECRET_KEY_BASE"].presence ||
      Mcweb::LocalConfig.load["secret_key_base"].presence
    if secret_key_base
      config.secret_key_base = secret_key_base
    end

    config.time_zone = "UTC"
    config.i18n.available_locales = [ "zh-CN", :en ]
    config.i18n.default_locale = "zh-CN"
    config.i18n.fallbacks = [ :en ]

    config.active_job.queue_adapter = :sidekiq
    config.action_mailbox.ingress = ENV.fetch("MCWEB_ACTION_MAILBOX_INGRESS", "relay").to_sym
    config.middleware.insert_before 0, Mcweb::RequestPerformanceMiddleware

    config.generators do |g|
      g.test_framework :minitest, fixture: false
      g.system_tests = :test
    end

    config.view_component.generate.preview_path = Rails.root.join("spec/components/previews")
  end
end
