# frozen_string_literal: true

module Commerce
  class DownloadsController < ApplicationController
    before_action :require_login

    def show
      payload = Rails.application.message_verifier(:commerce_download).verify(params[:token])
      return head :forbidden if payload["user_id"] != current_user.id
      return head :gone if payload["exp"].to_i < Time.current.to_i

      order_item = Commerce::OrderItem.find_by(id: payload["order_item_id"])
      return head :not_found unless order_item
      return head :forbidden unless order_item.order.user_id == current_user.id

      snapshot = order_item.fulfillment_snapshot || {}
      config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
      url = config["download_url"] || config[:download_url]
      return head :not_found if url.blank?

      redirect_to url, allow_other_host: true
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      head :forbidden
    end
  end
end
