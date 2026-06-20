# frozen_string_literal: true

module Community
  module InAppNotification
    module_function

    def notify(user:, notification_type:, key:, metadata:, notification_title: nil, notification_body: nil, title_key: nil, body_key: nil, **i18n_options)
      Notification.notify!(
        user: user,
        notification_type: notification_type,
        title: notification_title || t(title_key || "#{key}.title", **i18n_options),
        body: notification_body || t(body_key || "#{key}.body", **i18n_options),
        metadata: metadata
      )
    end

    def t(suffix, **options)
      I18n.t("mcweb.forum.in_app.#{suffix}", **options)
    end
  end
end
