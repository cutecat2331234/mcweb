# frozen_string_literal: true

module Community
  class ConversationMessagesController < ApplicationController
    before_action :require_login
    before_action :set_conversation

    def create
      result = Community::SendMessage.call(
        user: current_user,
        conversation: @conversation,
        body: message_params[:body]
      )

      if result.success?
        redirect_to forum_conversation_path(@conversation)
      else
        redirect_to forum_conversation_path(@conversation), alert: service_error_message(result)
      end
    end

    private

    def set_conversation
      @conversation = Community::Conversation.for_user(current_user).find(params[:conversation_id])
    end

    def message_params
      params.require(:message).permit(:body)
    end
  end
end
