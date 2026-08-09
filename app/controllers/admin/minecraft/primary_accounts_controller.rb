# frozen_string_literal: true

module Admin
  module Minecraft
    class PrimaryAccountsController < BaseController
      before_action -> { require_permission("minecraft.primary_accounts.switch_for_user") }

      def create
        user = User.find(params[:user_id])
        link = ::Minecraft::IdentityLink.find_by(
          id: params[:identity_link_id],
          user: user
        )
        result = ::Minecraft::AdministratorSetPrimaryAccount.call(
          user: user,
          target_identity_link: link,
          actor: current_user,
          reason: params[:reason],
          idempotency_key: params[:idempotency_key].presence || request.request_id
        )

        if result.success?
          redirect_to admin_minecraft_players_path,
                      notice: t("mcweb.flash.primary_account_changed")
        else
          redirect_to admin_minecraft_players_path, alert: service_error_message(result)
        end
      end
    end
  end
end
