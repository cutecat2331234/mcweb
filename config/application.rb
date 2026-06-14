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
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Mcweb
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "UTC"
    config.i18n.available_locales = [ "zh-CN", :en ]
    config.i18n.default_locale = "zh-CN"
    config.i18n.fallbacks = [ :en ]

    config.active_job.queue_adapter = :solid_queue
    config.mission_control.jobs.http_basic_auth_enabled = false
    config.mission_control.jobs.base_controller_class = "Admin::BaseController"

    config.generators do |g|
      g.test_framework :minitest, fixture: false
      g.system_tests = :test
    end

    config.view_component.generate.preview_path = Rails.root.join("spec/components/previews")
  end
end
