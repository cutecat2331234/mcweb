# frozen_string_literal: true

module Admin
  module System
    class SettingsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      BOOLEAN_ZERO_ONE_KEYS = %w[
        forum.auto_close_on_solved
        forum.group_pm_creator_only_add
        minecraft.backup.enabled
        minecraft.commerce.pause_fulfill_during_maintenance
        minecraft.graceful_stop.enabled
      ].freeze

      NUMBER_KEYS = %w[
        forum.bump_cooldown_hours
        forum.digest_hour
        forum.points.daily_check_in
        forum.points.post_created
        forum.points.reaction_received
        forum.points.solution_accepted
        forum.report_auto_hide_threshold
        forum.require_post_approval_below_tl
        forum.saved_search_digest_hour
        forum.saved_search_limit
        forum.warning_block_links_threshold
        forum.warning_block_pm_threshold
        forum.warning_block_post_threshold
        forum.warning_mute_days
        forum.warning_mute_threshold
        forum.warning_points_expire_days
        minecraft.graceful_stop.countdown_seconds
        store.cart_max_items
        store.compare_max_items
        store.flat_shipping_cents
        store.free_shipping_min_order_cents
        store.gift_wrap_cents
        store.min_checkout_subtotal_cents
        store.pending_order_expiry_minutes
        store.refund_window_days
        store.review_request_delay_days
        webhook.failure_alert_cooldown_hours
        webhook.failure_alert_forum_threshold
        webhook.failure_alert_store_threshold
        webhook.failure_alert_threshold
      ].freeze

      MULTILINE_KEYS = %w[
        forum.event_webhook_events
        forum.reaction_emojis
        minecraft.graceful_stop.commands
        minecraft.graceful_stop.message
        store.shipping_methods
      ].freeze

      READ_ONLY_KEYS = %w[
        forum.online_peak_at
        forum.online_peak_count
      ].freeze

      def show
        settings = SiteSetting.order(:key)

        render inertia: "Admin/System/Settings/Show", props: {
          settings: settings.map { |setting| setting_props(setting) }
        }
      end

      def update
        settings_params.each do |key, value|
          SiteSetting.set(key, value)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.settings_updated",
          metadata: { keys: settings_params.keys }
        )

        redirect_to admin_system_settings_path, notice: t("mcweb.flash.system_settings_saved")
      end

      private

      def setting_props(setting)
        value = setting.value.is_a?(String) ? setting.value : setting.value.to_json
        boolean = boolean_setting?(setting.key, value)
        one_zero = boolean && value.in?(%w[0 1])
        control = setting_control(setting.key, boolean)

        {
          key: setting.key,
          value: value,
          category: setting.key.split(".").first,
          control: control,
          wide: control == "textarea",
          enabled_value: one_zero ? "1" : "true",
          disabled_value: one_zero ? "0" : "false"
        }
      end

      def setting_control(key, boolean)
        return "readonly" if READ_ONLY_KEYS.include?(key)
        return "boolean" if boolean
        return "number" if NUMBER_KEYS.include?(key)
        return "textarea" if MULTILINE_KEYS.include?(key)
        return "password" if key.end_with?("_secret", "_private_key")

        "text"
      end

      def boolean_setting?(key, value)
        return true if value.in?(%w[true false])
        return false unless value.in?(%w[0 1])

        BOOLEAN_ZERO_ONE_KEYS.include?(key) ||
          key.start_with?("store.features.") ||
          key.match?(/\Aforum\..+_enabled\z/)
      end

      def settings_params
        allowed_keys = SiteSetting.pluck(:key)
        params.fetch(:settings, {}).permit(*allowed_keys).to_h
      end
    end
  end
end
