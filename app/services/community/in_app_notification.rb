# frozen_string_literal: true

module Community
  module InAppNotification
    module_function

    def notify(user:, notification_type:, key:, metadata:, notification_title: nil, notification_body: nil, title_key: nil, body_key: nil, **i18n_options)
      I18n.with_locale(Mcweb::LocaleResolver.resolve(user&.locale)) do
        resolved_options = i18n_options.transform_values { |value| resolve_value(value) }
        Notification.notify!(
          user: user,
          notification_type: notification_type,
          title: resolve_value(notification_title) || t(title_key || "#{key}.title", **resolved_options),
          body: resolve_value(notification_body) || t(body_key || "#{key}.body", **resolved_options),
          metadata: metadata
        )
      end
    end

    def t(suffix, **options)
      key = suffix.to_s
      key = "mcweb.forum.in_app.#{key}" unless key.start_with?("mcweb.")
      I18n.t(key, **options)
    end

    def resolve_value(value)
      value.respond_to?(:call) ? value.call : value
    end
  end
end
