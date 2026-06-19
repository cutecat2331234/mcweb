# frozen_string_literal: true

module Community
  class ConversationParticipantsController < ApplicationController
    before_action :require_login
    before_action :set_conversation

    def create
      result = Community::AddConversationParticipant.call(
        actor: current_user,
        conversation: @conversation,
        username: params[:username]
      )

      if result.success?
        redirect_to forum_conversation_path(@conversation), notice: t("mcweb.flash.participant_added")
      else
        redirect_to forum_conversation_path(@conversation), alert: service_error_message(result)
      end
    end

    def destroy
      result = Community::RemoveConversationParticipant.call(
        actor: current_user,
        conversation: @conversation,
        username: params[:username]
      )

      if result.success?
        if result.value.participant?(current_user)
          redirect_to forum_conversation_path(@conversation), notice: t("mcweb.flash.participant_removed")
        else
          redirect_to forum_conversations_path, notice: t("mcweb.flash.left_group")
        end
      else
        redirect_to forum_conversation_path(@conversation), alert: service_error_message(result)
      end
    end

    private

    def set_conversation
      @conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:conversation_id])
    end
  end
end
