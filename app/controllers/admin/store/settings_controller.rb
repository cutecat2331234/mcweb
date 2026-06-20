# frozen_string_literal: true

module Admin
  module Store
    class SettingsController < Admin::BaseController
      before_action -> { require_admin_module!("system") }
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
          storeFeatures: Commerce::StoreFeatures.admin_props,
          shippingMethods: Commerce::ShippingMethods.stored_list,
          testWebhookUrl: test_webhook_admin_store_settings_path,
          testAllWebhooksUrl: test_all_webhooks_admin_store_settings_path,
          testWebhookStatusUrl: webhook_test_status_admin_store_settings_path,
          testWebhookEvents: Commerce::DispatchTestOrderWebhook::EVENT_TYPES,
          lastTestWebhook: WebhookTestDeliveryStatus.store_last
        }
      end

      def update
        if params[:store_features].present?
          Commerce::StoreFeatures.update_from_params!(params[:store_features])
        end

        if params[:shipping_methods].present?
          json = normalize_shipping_methods(params[:shipping_methods]).to_json
          validate_shipping_methods!(json)
          SiteSetting.set("store.shipping_methods", json)
        end

        settings_params.each do |key, value|
          validate_setting_value!(key, value)
          SiteSetting.set(key, value)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.store_settings_updated",
          metadata: { keys: settings_params.keys + (params[:shipping_methods].present? ? [ "store.shipping_methods" ] : []) + (params[:store_features].present? ? Commerce::StoreFeatures.definitions.map(&:key) : []) }
        )

        redirect_to admin_store_settings_path, notice: t("mcweb.flash.store_settings_saved")
      rescue ArgumentError, JSON::ParserError => e
        redirect_to admin_store_settings_path, alert: t("mcweb.flash.store_settings_save_failed", message: e.message)
      end

      def test_webhook
        event_type = params[:event].to_s.presence || "order.test"
        result = Commerce::DispatchTestOrderWebhook.call(event_type: event_type)
        if result.success?
          redirect_to admin_store_settings_path, notice: t("mcweb.flash.webhook_test_queued", label: result.value[:event_type])
        else
          redirect_to admin_store_settings_path, alert: result.error || t("mcweb.flash.webhook_test_failed")
        end
      end

      def test_all_webhooks
        result = Commerce::BatchTestOrderWebhooks.call
        if result.success?
          redirect_to admin_store_settings_path,
                      notice: t("mcweb.flash.webhook_batch_order_test_queued", queued: result.value[:queued], total: result.value[:total])
        else
          redirect_to admin_store_settings_path, alert: result.error || t("mcweb.flash.webhook_batch_test_failed")
        end
      end

      def webhook_test_status
        render json: { lastTestWebhook: WebhookTestDeliveryStatus.store_last }
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
        labels = I18n.t("mcweb.admin.store.settings.labels")
        return key unless labels.is_a?(Hash)

        labels[key.to_sym] || labels[key] || key
      end

      def setting_hint(key)
        hints = I18n.t("mcweb.admin.store.settings.hints")
        return nil unless hints.is_a?(Hash)

        hints[key.to_sym] || hints[key]
      end

      def setting_input_type(key)
        return "text" if %w[store.seo_title store.seo_description store.abandoned_cart_coupon_code store.order_webhook_secret store.order_webhook_url].include?(key)

        "number"
      end

      def validate_shipping_methods!(json)
        parsed = JSON.parse(json)
        raise ArgumentError, t("mcweb.admin.store.settings.errors.shipping_methods_required") if parsed.blank?
        raise ArgumentError, t("mcweb.admin.store.settings.errors.shipping_methods_invalid") unless parsed.is_a?(Array)
      end

      def validate_setting_value!(key, value)
        return unless key == "store.order_webhook_url"

        url = value.to_s.strip
        return if url.blank?
        return if UrlSafety.public_http_url?(url)

        raise ArgumentError, t("mcweb.admin.store.settings.errors.webhook_url_private")
      end
    end
  end
end
