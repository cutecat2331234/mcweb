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
        body: message_params[:body],
        attachment_ids: message_params[:attachment_ids],
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to forum_conversation_path(@conversation)
      else
        apply_retry_after_header(result)
        render inertia: "Community/Messages/Show",
               status: service_error_status(result),
               props: conversation_show_props(
                 @conversation,
                 form_errors: inertia_form_errors(result, prefix: "message"),
                 initialBody: message_params[:body]
               )
      end
    end

    def update
      message = @conversation.messages.find(params[:id])
      result = Community::EditMessage.call(
        user: current_user,
        message: message,
        body: message_params[:body],
        expected_revision: message_params[:expected_revision]
      )

      if result.success?
        redirect_to forum_conversation_path(@conversation), notice: t("mcweb.flash.message_updated", default: "消息已更新")
      else
        redirect_to forum_conversation_path(@conversation), alert: service_error_message(result)
      end
    end

    def destroy
      message = @conversation.messages.find(params[:id])
      result = Community::DeleteMessage.call(user: current_user, message: message)
      return head :forbidden if result.failure?

      redirect_to forum_conversation_path(@conversation), notice: t("mcweb.flash.message_deleted", default: "消息已删除")
    end

    private

    def set_conversation
      @conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:conversation_id])
    end

    def message_params
      params.require(:message).permit(:body, :expected_revision, attachment_ids: [])
    end
  end
end
