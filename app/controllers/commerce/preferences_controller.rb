# frozen_string_literal: true

module Commerce
  class PreferencesController < ApplicationController
    before_action :require_login

    NOTIFICATION_TYPES = %w[
      commerce.order_created
      commerce.payment_confirmed
      commerce.order_fulfilled
      commerce.order_cancelled
      commerce.refund_processed
      commerce.abandoned_cart
    ].freeze

    CHANNELS = %w[email].freeze

    def show
      prefs = NOTIFICATION_TYPES.map do |type|
        {
          notification_type: type,
          label: notification_label(type),
          email: NotificationPreference.enabled?(current_user, channel: "email", notification_type: type)
        }
      end

      render inertia: "Commerce/Preferences/Show", props: { preferences: prefs }
    end

    def update
      NOTIFICATION_TYPES.each do |type|
        enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:preferences, type, :email))
        NotificationPreference.set!(
          current_user,
          channel: "email",
          notification_type: type,
          enabled: enabled
        )
      end

      redirect_to store_preferences_path, notice: "商城邮件偏好已保存。"
    end

    private

    def notification_label(type)
      {
        "commerce.order_created" => "订单确认",
        "commerce.payment_confirmed" => "支付成功",
        "commerce.order_fulfilled" => "发货完成",
        "commerce.order_cancelled" => "订单取消",
        "commerce.refund_processed" => "退款通知",
        "commerce.abandoned_cart" => "购物车提醒"
      }[type] || type.humanize
    end
  end
end
