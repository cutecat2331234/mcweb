# frozen_string_literal: true

module Minecraft
  class IdentityLinksController < ApplicationController
    include PrivateNoStoreResponse

    before_action :require_login
    before_action :rate_limit_unlink_attempts!, only: :destroy

    def destroy
      link = Minecraft::IdentityLink.find_by(id: params[:id], user: current_user)
      return head :not_found unless link

      result = Minecraft::UnlinkIdentity.call(
        user: current_user,
        identity_link: link,
        actor: current_user,
        confirmation: unlink_params[:confirmation],
        lock_version: unlink_params[:lock_version],
        idempotency_key: unlink_params[:idempotency_key],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to minecraft_link_path, notice: t("mcweb.flash.minecraft_identity_unlinked")
      else
        redirect_to minecraft_link_path, alert: service_error_message(result)
      end
    end

    private

    def unlink_params
      params.permit(:confirmation, :lock_version, :idempotency_key)
    end

    def rate_limit_unlink_attempts!
      result = Administration::AbuseRateLimit.call(
        action: :minecraft_identity_unlink,
        account: current_user,
        ip_address: request.remote_ip
      )
      return if result.success?

      apply_retry_after_header(result)
      redirect_to minecraft_link_path, alert: service_error_message(result)
    end
  end
end
