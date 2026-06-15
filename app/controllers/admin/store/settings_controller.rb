# frozen_string_literal: true

module Admin
  module Store
    class SettingsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      STORE_SETTING_KEYS = %w[
        store.seo_title
        store.seo_description
        store.free_shipping_min_order_cents
        store.flat_shipping_cents
        store.gift_wrap_cents
        store.min_checkout_subtotal_cents
        store.refund_window_days
        store.pending_order_expiry_minutes
        store.review_request_delay_days
        store.compare_max_items
        store.cart_max_items
        store.abandoned_cart_coupon_code
        store.order_webhook_secret
        store.order_webhook_url
      ].freeze

      def show
        render inertia: "Admin/Store/Settings/Show", props: {
          settings: store_settings_props,
          shippingMethods: Commerce::ShippingMethods.stored_list,
          testWebhookUrl: test_webhook_admin_store_settings_path,
          testWebhookEvents: Commerce::DispatchTestOrderWebhook::EVENT_TYPES
        }
      end

      def update
        if params[:shipping_methods].present?
          json = normalize_shipping_methods(params[:shipping_methods]).to_json
          validate_shipping_methods!(json)
          SiteSetting.set("store.shipping_methods", json)
        end

        settings_params.each do |key, value|
          SiteSetting.set(key, value)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.store_settings_updated",
          metadata: { keys: settings_params.keys + (params[:shipping_methods].present? ? [ "store.shipping_methods" ] : []) }
        )

        redirect_to admin_store_settings_path, notice: "商城设置已保存。"
      rescue ArgumentError, JSON::ParserError => e
        redirect_to admin_store_settings_path, alert: "保存失败：#{e.message}"
      end

      def test_webhook
        event_type = params[:event].to_s.presence || "order.test"
        result = Commerce::DispatchTestOrderWebhook.call(event_type: event_type)
        if result.success?
          redirect_to admin_store_settings_path, notice: "测试 Webhook 已加入发送队列（#{result.value[:event_type]}）。"
        else
          redirect_to admin_store_settings_path, alert: result.error || "测试发送失败。"
        end
      end

    private

      def store_settings_props
        STORE_SETTING_KEYS.map do |key|
          {
            key: key,
            value: SiteSetting.get(key, default_for(key)).to_s,
            label: setting_label(key),
            hint: setting_hint(key),
            input_type: setting_input_type(key)
          }
        end
      end

      def settings_params
        allowed = STORE_SETTING_KEYS.index_with { |_k| nil }
        params.fetch(:settings, {}).permit(*allowed.keys).to_h
      end

      def normalize_shipping_methods(raw)
        Array(raw).filter_map do |entry|
          next unless entry.is_a?(ActionController::Parameters) || entry.is_a?(Hash)

          data = entry.to_unsafe_h.symbolize_keys
          code = data[:code].to_s.strip
          next if code.blank?

          {
            "code" => code,
            "label" => data[:label].to_s.strip.presence || code,
            "cents" => data[:cents].to_i,
            "delivery_days_min" => data[:delivery_days_min].presence&.to_i,
            "delivery_days_max" => data[:delivery_days_max].presence&.to_i
          }
        end
      end

      def default_for(key)
        {
          "store.gift_wrap_cents" => "500",
          "store.pending_order_expiry_minutes" => "30",
          "store.review_request_delay_days" => "3",
          "store.compare_max_items" => "4",
          "store.cart_max_items" => "99"
        }[key] || "0"
      end

      def setting_label(key)
        {
          "store.seo_title" => "商城 SEO 标题",
          "store.seo_description" => "商城 SEO 描述",
          "store.free_shipping_min_order_cents" => "免运费最低订单（分）",
          "store.flat_shipping_cents" => "固定运费（分）",
          "store.gift_wrap_cents" => "礼品包装费（分）",
          "store.min_checkout_subtotal_cents" => "最低结账金额（分）",
          "store.refund_window_days" => "退款窗口（天）",
          "store.pending_order_expiry_minutes" => "待支付订单过期（分钟）",
          "store.review_request_delay_days" => "评价邀请延迟（天）",
          "store.compare_max_items" => "对比列表上限",
          "store.cart_max_items" => "购物车商品种类上限",
          "store.abandoned_cart_coupon_code" => "弃购提醒优惠券代码",
          "store.order_webhook_secret" => "订单 Webhook 密钥",
          "store.order_webhook_url" => "订单 Webhook URL"
        }[key] || key
      end

      def setting_hint(key)
        {
          "store.free_shipping_min_order_cents" => "订单小计达到此金额（分）免运费，0 表示不启用。",
          "store.refund_window_days" => "0 表示不允许用户自助申请退款。",
          "store.compare_max_items" => "用户可同时对比的商品数量（对标 XenForo 资源对比）。",
          "store.cart_max_items" => "购物车中不同商品种类上限，0 表示不限制。",
          "store.abandoned_cart_coupon_code" => "弃购邮件中附带的优惠券，留空则不发放。",
          "store.flat_shipping_cents" => "结账时「标准配送」的实际运费（分），会覆盖下方配送方式中 standard 的价格。",
          "store.order_webhook_url" => "订单状态变更时 POST JSON 的目标 URL，留空则不发送。",
          "store.order_webhook_secret" => "用于 X-McWeb-Signature HMAC 签名的密钥，可选。"
        }[key]
      end

      def setting_input_type(key)
        return "text" if %w[store.seo_title store.seo_description store.abandoned_cart_coupon_code store.order_webhook_secret store.order_webhook_url].include?(key)

        "number"
      end

      def validate_shipping_methods!(json)
        parsed = JSON.parse(json)
        raise ArgumentError, "至少保留一种配送方式" if parsed.blank?
        raise ArgumentError, "配送方式必须是 JSON 数组" unless parsed.is_a?(Array)
      end
    end
  end
end
