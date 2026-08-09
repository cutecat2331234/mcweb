# frozen_string_literal: true

module Admin
  module Minecraft
    class PrimaryAccountChangeRequestsController < BaseController
      before_action -> { require_permission("minecraft.primary_accounts.review") }

      def update
        request_record = ::Minecraft::PrimaryAccountChangeRequest.find(params[:id])
        result = ::Minecraft::DecidePrimaryAccountChangeRequest.call(
          request_record: request_record,
          actor: current_user,
          action: params[:decision],
          reason: params[:reason],
          lock_version: params[:lock_version],
          idempotency_key: params[:idempotency_key].presence || request.request_id
        )

        if result.success?
          redirect_to admin_minecraft_players_path,
                      notice: t("mcweb.flash.primary_account_request_decided")
        else
          redirect_to admin_minecraft_players_path, alert: service_error_message(result)
        end
      end
    end
  end
end
