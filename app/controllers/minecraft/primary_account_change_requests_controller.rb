# frozen_string_literal: true

module Minecraft
  class PrimaryAccountChangeRequestsController < ApplicationController
    before_action :require_login

    def destroy
      request_record = Minecraft::PrimaryAccountChangeRequest.find_by(
        id: params[:id],
        user: current_user
      )
      return head :not_found unless request_record

      result = Minecraft::CancelPrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: current_user,
        lock_version: params[:lock_version]
      )

      if result.success?
        redirect_to minecraft_link_path, notice: t("mcweb.flash.primary_account_change_cancelled")
      else
        redirect_to minecraft_link_path, alert: service_error_message(result)
      end
    end
  end
end
