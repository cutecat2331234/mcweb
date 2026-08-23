# frozen_string_literal: true

module Community
  class ConversationInvitationsController < ApplicationController
    include PrivateNoStoreResponse

    before_action :require_login
    before_action :set_invitation

    def accept
      result = Community::AcceptConversationInvitation.call(
        user: current_user,
        invitation: @invitation
      )

      if result.success?
        redirect_to forum_conversation_path(result.value), notice: t("mcweb.flash.conversation_invitation_accepted")
      else
        redirect_to forum_conversations_path, alert: service_error_message(result)
      end
    end

    def decline
      result = Community::DeclineConversationInvitation.call(
        user: current_user,
        invitation: @invitation
      )

      if result.success?
        redirect_to forum_conversations_path, notice: t("mcweb.flash.conversation_invitation_declined")
      else
        redirect_to forum_conversations_path, alert: service_error_message(result)
      end
    end

    private

    def set_invitation
      @invitation = Community::ConversationInvitation.find_by!(
        public_id: params[:id],
        user: current_user
      )
    end
  end
end
