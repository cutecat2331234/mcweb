# frozen_string_literal: true

module Commerce
  module InAppNotification
    module_function

    def order_event(user:, notification_type:, key:, order:, path: nil, body: nil, **options)
      with_recipient_locale(user) do
        resolved_options = resolve_options(options)
        base = "mcweb.commerce.in_app.#{key}"
        Commerce::NotifyOrderEvent.call(
          user: user,
          notification_type: notification_type,
          title: I18n.t("#{base}.title", number: order.order_number, **resolved_options),
          body: resolve_value(body) || I18n.t("#{base}.body", number: order.order_number, **resolved_options),
          path: path || order_path(order)
        )
      end
    end

    def product_event(user:, notification_type:, key:, product:, path:, body: nil, **options)
      translation_options = { product: product.name }.merge(options.except(:metadata))
      notify(
        user: user,
        notification_type: notification_type,
        title_key: "#{key}.title",
        body_key: "#{key}.body",
        title_options: translation_options,
        body_options: translation_options,
        body: body,
        metadata: {
          path: path,
          product_public_id: product.public_id
        }.merge(options[:metadata] || {})
      )
    end

    def generic(user:, notification_type:, key:, path:, **options)
      translation_options = options.except(:metadata)
      notify(
        user: user,
        notification_type: notification_type,
        title_key: "#{key}.title",
        body_key: "#{key}.body",
        title_options: translation_options,
        body_options: translation_options,
        metadata: { path: path }.merge(options[:metadata] || {})
      )
    end

    def notify(user:, notification_type:, metadata:, title: nil, body: nil,
               title_key: nil, body_key: nil, title_options: {}, body_options: {})
      with_recipient_locale(user) do
        Notification.notify!(
          user: user,
          notification_type: notification_type,
          title: resolve_value(title) || translate(title_key, **resolve_options(title_options)),
          body: resolve_value(body) || translate(body_key, **resolve_options(body_options)),
          metadata: metadata
        )
      end
    end

    def with_recipient_locale(user, &block)
      I18n.with_locale(Mcweb::LocaleResolver.resolve(user&.locale), &block)
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

    def translate(key, **options)
      key = key.to_s
      return I18n.t(key, **options) if key.start_with?("mcweb.")

      t(key, **options)
    end

    def resolve_options(options)
      resolve_value(options).to_h.transform_values { |value| resolve_value(value) }
    end

    def resolve_value(value)
      value.respond_to?(:call) ? value.call : value
    end
  end
end
