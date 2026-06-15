# frozen_string_literal: true

module Commerce
  class PreferencesController < ApplicationController
    before_action :require_login

    NOTIFICATION_TYPES = %w[
      commerce.order_created
      commerce.payment_confirmed
      commerce.order_processing
      commerce.order_fulfilling
      commerce.order_fulfilled
      commerce.order_shipped
      commerce.order_completed
      commerce.order_cancelled
      commerce.refund_requested
      commerce.refund_processed
      commerce.refund_rejected
      commerce.abandoned_cart
      commerce.stock_restocked
      commerce.price_drop
      commerce.product_changelog
      commerce.question_answered
      commerce.new_product_question
      commerce.merchant_review_reply
      commerce.review_request
      commerce.product_available
    ].freeze

    CHANNELS = %w[email in_app].freeze

    def show
      prefs = NOTIFICATION_TYPES.map do |type|
        {
          notification_type: type,
          label: notification_label(type),
          email: NotificationPreference.enabled?(current_user, channel: "email", notification_type: type),
          in_app: NotificationPreference.enabled?(current_user, channel: "in_app", notification_type: type)
        }
      end

      if staff_notifications?
        prefs << {
          notification_type: "commerce.low_stock",
          label: "低库存提醒（员工）",
          email: NotificationPreference.enabled?(current_user, channel: "email", notification_type: "commerce.low_stock"),
          in_app: NotificationPreference.enabled?(current_user, channel: "in_app", notification_type: "commerce.low_stock")
        }
      end

      render inertia: "Commerce/Preferences/Show", props: { preferences: prefs }
    end

    def update
      types = NOTIFICATION_TYPES.dup
      types << "commerce.low_stock" if staff_notifications?

      types.each do |type|
        CHANNELS.each do |channel|
          enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:preferences, type, channel))
          next if enabled.nil?

          NotificationPreference.set!(
            current_user,
            channel: channel,
            notification_type: type,
            enabled: enabled
          )
        end
      end

      redirect_to store_preferences_path, notice: "商城通知偏好已保存。"
    end

    private

    def staff_notifications?
      current_user.permission?("store.products.read") || current_user.permission?("admin.access")
    end

    def notification_label(type)
      {
        "commerce.order_created" => "订单确认",
        "commerce.payment_confirmed" => "支付成功",
        "commerce.order_processing" => "订单处理中",
        "commerce.order_fulfilling" => "发货处理中",
        "commerce.order_fulfilled" => "发货完成",
        "commerce.order_shipped" => "物流发货",
        "commerce.order_completed" => "订单完成",
        "commerce.order_cancelled" => "订单取消",
        "commerce.refund_requested" => "退款申请提交",
        "commerce.refund_processed" => "退款通知",
        "commerce.refund_rejected" => "退款拒绝通知",
        "commerce.abandoned_cart" => "购物车提醒",
        "commerce.stock_restocked" => "到货通知",
        "commerce.price_drop" => "降价提醒",
        "commerce.product_changelog" => "商品更新日志",
        "commerce.question_answered" => "问答回复通知",
        "commerce.new_product_question" => "新商品提问（员工）",
        "commerce.merchant_review_reply" => "商家评价回复",
        "commerce.review_request" => "购后评价邀请",
        "commerce.product_available" => "商品上架通知"
      }[type] || type.humanize
    end
  end
end
