# frozen_string_literal: true

module Community
  class ConversationMessageDraftsController < ApplicationController
    before_action :require_login
    before_action :set_conversation

    def update
      result = Community::SaveMessageDraft.call(user: current_user, conversation: @conversation, body: params[:body])

      if result.success?
        head :no_content
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def destroy
      Community::MessageDraft.where(user: current_user, conversation: @conversation).delete_all
      head :no_content
    end

    private

    def set_conversation
      @conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:conversation_id])
    end
  end
end
