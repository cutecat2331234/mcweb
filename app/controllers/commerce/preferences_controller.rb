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
      commerce.payment_reminder
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
          label: Community::NotificationTypeLabels.label_for("commerce.low_stock_staff"),
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

      redirect_to store_preferences_path, notice: t("mcweb.flash.store_preferences_saved")
    end

    private

    def staff_notifications?
      current_user.permission?("store.products.read") || current_user.permission?("admin.access")
    end

    def notification_label(type)
      Community::NotificationTypeLabels.label_for(type)
    end
  end
end
