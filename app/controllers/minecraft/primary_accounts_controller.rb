# frozen_string_literal: true

module Minecraft
  class PrimaryAccountsController < ApplicationController
    include PrivateNoStoreResponse

    before_action :require_login

    def create
      link = Minecraft::IdentityLink.find_by(id: params[:id])
      result = Minecraft::RequestPrimaryAccountChange.call(
        user: current_user,
        target_identity_link: link,
        actor: current_user,
        reason: params[:reason],
        idempotency_key: params[:idempotency_key].presence || request.request_id
      )

      if result.success?
        notice_key = result.value[:request] ?
          "mcweb.flash.primary_account_change_requested" :
          "mcweb.flash.primary_account_changed"
        redirect_to minecraft_link_path, notice: t(notice_key)
      else
        redirect_to minecraft_link_path, alert: service_error_message(result)
      end
    end
  end
end
