# frozen_string_literal: true

Rails.application.config.after_initialize do
  settings = Mcweb::DeveloperMode.settings
  vite_profile = defined?(ViteRuby) ? ViteRuby.config.mode : "unavailable"

  Rails.logger.info(
    "[mcweb.runtime] rails=#{Rails.env} " \
    "developer_mode=#{settings.enabled?} " \
    "security_profile=#{settings.enabled? ? settings.profile : 'production'} " \
    "runtime_profile=#{settings.runtime_profile} " \
    "vite_profile=#{vite_profile}"
  )

  Operations::AuditDeveloperModeConfiguration.call(settings:)
end
