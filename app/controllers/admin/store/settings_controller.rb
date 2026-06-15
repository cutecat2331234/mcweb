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
        store.shipping_methods
      ].freeze

      def show
        render inertia: "Admin/Store/Settings/Show", props: {
          settings: store_settings_props
        }
      end

      def update
        settings_params.each do |key, value|
          validate_setting!(key, value)
          SiteSetting.set(key, value)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.store_settings_updated",
          metadata: { keys: settings_params.keys }
        )

        redirect_to admin_store_settings_path, notice: "商城设置已保存。"
      rescue ArgumentError, JSON::ParserError => e
        redirect_to admin_store_settings_path, alert: "保存失败：#{e.message}"
      end

    private

      def store_settings_props
        STORE_SETTING_KEYS.map do |key|
          value = SiteSetting.get(key, default_for(key)).to_s
          value = JSON.pretty_generate(JSON.parse(value)) if key == "store.shipping_methods" && value.present?
          {
            key: key,
            value: value,
            label: setting_label(key),
            hint: setting_hint(key),
            input_type: setting_input_type(key)
          }
        rescue JSON::ParserError
          {
            key: key,
            value: value,
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

      def default_for(key)
        return Commerce::ShippingMethods::DEFAULT_JSON.to_json if key == "store.shipping_methods"

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
          "store.shipping_methods" => "配送方式（JSON）"
        }[key] || key
      end

      def setting_hint(key)
        {
          "store.free_shipping_min_order_cents" => "订单小计达到此金额（分）免运费，0 表示不启用。",
          "store.refund_window_days" => "0 表示不允许用户自助申请退款。",
          "store.compare_max_items" => "用户可同时对比的商品数量（对标 XenForo 资源对比）。",
          "store.cart_max_items" => "购物车中不同商品种类上限，0 表示不限制。",
          "store.abandoned_cart_coupon_code" => "弃购邮件中附带的优惠券，留空则不发放。",
          "store.shipping_methods" => "JSON 数组，每项含 code、label、cents、delivery_days_min、delivery_days_max。标准配送运费会同步 flat_shipping_cents。"
        }[key]
      end

      def setting_input_type(key)
        return "json" if key == "store.shipping_methods"
        return "text" if %w[store.seo_title store.seo_description store.abandoned_cart_coupon_code store.order_webhook_secret].include?(key)

        "number"
      end

      def validate_setting!(key, value)
        return unless key == "store.shipping_methods" && value.present?

        parsed = JSON.parse(value)
        raise ArgumentError, "配送方式必须是 JSON 数组" unless parsed.is_a?(Array)
      end
    end
  end
end
