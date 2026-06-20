# frozen_string_literal: true

local_key = Mcweb::LocalConfig.load["lockbox_master_key"]
Lockbox.master_key = local_key if local_key.present?

Lockbox.master_key ||= Rails.application.credentials.dig(:lockbox, :master_key)

if Lockbox.master_key.blank?
  if Rails.env.production?
    raise "lockbox_master_key must be configured in config/local.yml or credentials for production"
  end

  Lockbox.master_key = "0" * 64
  Rails.logger.warn("[lockbox] Using development fallback master key; configure lockbox_master_key before production deploy")
end
