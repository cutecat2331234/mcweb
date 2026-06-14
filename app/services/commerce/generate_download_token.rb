# frozen_string_literal: true

module Commerce
  class GenerateDownloadToken < ApplicationService
    def initialize(order_item:, user:)
      @order_item = order_item
      @user = user
    end

    def call
      order = @order_item.order
      return ServiceResult.failure(error: "Order not accessible.") unless order.user_id == @user.id
      return ServiceResult.failure(error: "Order not paid.") unless %w[paid processing fulfilling fulfilled completed].include?(order.status)

      snapshot = @order_item.fulfillment_snapshot || {}
      config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
      url = config["download_url"] || config[:download_url]
      return ServiceResult.failure(error: "No download available.") if url.blank?

      payload = {
        order_item_id: @order_item.id,
        user_id: @user.id,
        exp: 1.hour.from_now.to_i
      }
      token = Rails.application.message_verifier(:commerce_download).generate(payload)
      ServiceResult.success(token: token, url: url)
    end
  end
end
