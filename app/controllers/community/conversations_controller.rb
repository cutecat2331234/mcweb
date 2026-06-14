# frozen_string_literal: true

module Community
  class ConversationsController < ApplicationController
    before_action :require_login

    def index
      conversations = Community::Conversation
        .for_user(current_user)
        .includes(participants: :user, messages: :user)
        .ordered
        .limit(50)

      render inertia: "Community/Messages/Index", props: {
        conversations: conversations.map { |conv| serialize_conversation(conv) }
      }
    end

    def show
      conversation = Community::Conversation.for_user(current_user).find(params[:id])
      conversation.mark_read_for!(current_user)

      @pagy, messages = pagy(
        conversation.messages.includes(:user).order(created_at: :asc),
        limit: 50
      )

      render inertia: "Community/Messages/Show", props: {
        conversation: serialize_conversation(conversation, include_other: true),
        messages: messages.map { |msg| serialize_message(msg) },
        pagination: pagy_props(@pagy)
      }
    end

    def new
      render inertia: "Community/Messages/New", props: {
        recipient: params[:to].to_s.presence
      }
    end

    def create
      result = Community::CreateConversation.call(
        sender: current_user,
        recipient_username: conversation_params[:recipient],
        body: conversation_params[:body]
      )

      if result.success?
        redirect_to forum_conversation_path(result.value[:conversation])
      else
        redirect_to new_forum_conversation_path(to: conversation_params[:recipient]),
                    alert: service_error_message(result)
      end
    end

    private

    def conversation_params
      params.require(:conversation).permit(:recipient, :body)
    end

    def serialize_conversation(conversation, include_other: false)
      other = conversation.other_user(current_user)
      last_message = conversation.messages.order(created_at: :desc).first

      data = {
        id: conversation.id,
        url: forum_conversation_path(conversation),
        last_message_at: conversation.last_message_at ? l(conversation.last_message_at, format: :short) : nil,
        unread_count: conversation.unread_count_for(current_user),
        last_message_preview: last_message&.body&.truncate(80)
      }

      if include_other && other
        data[:other_user] = {
          username: other.username,
          avatar_url: other.avatar_url,
          profile_url: forum_user_path(other.username)
        }
      elsif other
        data[:other_username] = other.username
        data[:avatar_url] = other.avatar_url
      end

      data
    end

    def serialize_message(message)
      formatted = Community::FormatPostBody.call(body: message.body)
      body_html = formatted.success? ? formatted.value : ERB::Util.html_escape(message.body)

      {
        id: message.id,
        body: message.body,
        body_html: body_html,
        author: message.user.username,
        avatar_url: message.user.avatar_url,
        is_mine: message.user_id == current_user.id,
        created_at: l(message.created_at, format: :short)
      }
    end
  end
end
