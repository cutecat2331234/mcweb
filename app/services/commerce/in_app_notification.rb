# frozen_string_literal: true

module Commerce
  module InAppNotification
    module_function

    def order_event(user:, notification_type:, key:, order:, path: nil, body: nil, **options)
      base = "mcweb.commerce.in_app.#{key}"
      Commerce::NotifyOrderEvent.call(
        user: user,
        notification_type: notification_type,
        title: I18n.t("#{base}.title", number: order.order_number, **options),
        body: body || I18n.t("#{base}.body", number: order.order_number, **options),
        path: path || order_path(order)
      )
    end

    def product_event(user:, notification_type:, key:, product:, path:, body: nil, **options)
      Notification.notify!(
        user: user,
        notification_type: notification_type,
        title: t("#{key}.title", product: product.name, **options),
        body: body || t("#{key}.body", product: product.name, **options),
        metadata: {
          path: path,
          product_public_id: product.public_id
        }.merge(options[:metadata] || {})
      )
    end

    def generic(user:, notification_type:, key:, path:, **options)
      Notification.notify!(
        user: user,
        notification_type: notification_type,
        title: t("#{key}.title", **options),
        body: t("#{key}.body", **options),
        metadata: { path: path }.merge(options[:metadata] || {})
      )
    end

    def order_status_label(status)
      I18n.t("mcweb.labels.order_status.#{status}", default: status.to_s.humanize)
    end

    def order_path(order)
      "#{Mcweb::Paths::APP_PREFIX}/store/orders/#{order.public_id}"
    end

    def t(suffix, **options)
      I18n.t("mcweb.commerce.in_app.#{suffix}", **options)
    end
  end
end
