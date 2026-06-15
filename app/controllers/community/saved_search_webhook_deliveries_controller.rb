# frozen_string_literal: true

module Community
  class SavedSearchWebhookDeliveriesController < ApplicationController
    before_action :require_login

    def retry
      delivery = Community::SavedSearchWebhookDelivery.find(params[:id])
      unless delivery.status == "failed"
        redirect_to forum_preferences_path, alert: "仅失败记录可重试。"
        return
      end

      result = Community::RetrySavedSearchWebhook.call(delivery: delivery, actor: current_user)

      if result.success?
        redirect_to forum_preferences_path, notice: "Webhook 已重新加入发送队列。"
      else
        redirect_to forum_preferences_path, alert: result.error || "重试失败。"
      end
    end
  end
end
