# frozen_string_literal: true

module Community
  class ConversationMessagesController < ApplicationController
    include Community::WarningRestrictionsSerializable
    include Community::ConversationsInertiaProps

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
        render inertia: "Community/Messages/Show",
               status: :unprocessable_entity,
               props: conversation_show_props(
                 @conversation,
                 form_errors: inertia_form_errors(result, prefix: "message"),
                 initialBody: message_params[:body]
               )
      end
    end

    def destroy
      message = @conversation.messages.find(params[:id])
      unless message.user_id == current_user.id || current_user.permission?("forum.topics.lock")
        return head :forbidden
      end

      message.soft_delete!
      redirect_to forum_conversation_path(@conversation), notice: t("mcweb.flash.message_deleted", default: "消息已删除")
    end

    private

    def set_conversation
      @conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:conversation_id])
    end

    def message_params
      params.require(:message).permit(:body)
    end
  end
end
