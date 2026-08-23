# frozen_string_literal: true

module RegisteredSiteSettingUpdates
  extend ActiveSupport::Concern

  private

  def normalize_registered_site_setting_updates(updates, owner:, surface: :dedicated)
    updates.each_with_object({}) do |(key, value), normalized|
      next if Mcweb::SettingsNamespaceRegistry.sensitive?(key) && value.blank?

      normalized[key.to_s] = Mcweb::SettingsNamespaceRegistry.normalize_for_write(
        key,
        value,
        surface:,
        owner:
      )
    end
  end

  def registered_site_setting_value(key, default = nil)
    value = SiteSetting.get(key, default)
    sensitive = Mcweb::SettingsNamespaceRegistry.sensitive?(key)

    {
      value: sensitive ? "" : value.to_s,
      sensitive:,
      configured: sensitive && value.present?,
      input_type: Mcweb::SettingsNamespaceRegistry.input_type_for(key).to_s
    }
  end

  def registered_site_setting_error(error)
    I18n.t(
      "mcweb.site_settings.errors.#{error.code}",
      **error.details,
      default: I18n.t("mcweb.site_settings.errors.invalid", key: error.key),
      key: error.key
    )
  end
end
