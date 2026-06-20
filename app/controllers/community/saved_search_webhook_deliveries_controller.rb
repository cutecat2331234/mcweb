# frozen_string_literal: true

module Community
  class SavedSearchWebhookDeliveriesController < ApplicationController
    before_action :require_login

    def retry
      delivery = Community::SavedSearchWebhookDelivery
        .joins(:saved_search)
        .where(forum_saved_searches: { user_id: current_user.id })
        .find(params[:id])
      unless delivery.status == "failed"
        redirect_to forum_preferences_path, alert: t("mcweb.flash.webhook_retry_failed_only")
        return
      end

      result = Community::RetrySavedSearchWebhook.call(delivery: delivery, actor: current_user)

      if result.success?
        redirect_to forum_preferences_path, notice: t("mcweb.flash.webhook_requeued")
      else
        redirect_to forum_preferences_path, alert: result.error || t("mcweb.flash.webhook_retry_failed")
      end
    end
  end
end
