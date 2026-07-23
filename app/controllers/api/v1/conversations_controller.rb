# frozen_string_literal: true

module Api
  module V1
    # Private conversations (PMs) for the user the API key acts as. Requires a
    # bound user; access is always scoped to conversations the user participates in.
    class ConversationsController < BaseController
      before_action :require_bound_user!
      skip_before_action :require_read_scope!, only: :reply
      before_action :require_writer!, only: :reply
      before_action :set_conversation, only: %i[show reply read]

      # GET /api/v1/conversations
      def index
        scope = Community::Conversation.for_user(api_user).ordered
        pagy, conversations = api_paginate(scope)
        render json: {
          data: conversations.map { |c| serialize_conversation(c) },
          meta: pagination_meta(pagy)
        }
      end

      # GET /api/v1/conversations/:id (with paginated messages; ?mark_read=true)
      def show
        @conversation.mark_read_for!(api_user) if params[:mark_read] == "true"
        pagy, messages = api_paginate(@conversation.messages.includes(:user).order(:created_at))
        render json: {
          data: serialize_conversation(@conversation).merge(messages: messages.map { |m| serialize_message(m) }),
          meta: pagination_meta(pagy)
        }
      end

      # POST /api/v1/conversations/:id/reply  (write scope)
      def reply
        result = Community::SendMessage.call(user: api_user, conversation: @conversation, body: params[:body].to_s)
        return render_service_error(result) if result.failure?

        render json: { data: serialize_message(result.value) }, status: :created
      end

      # POST /api/v1/conversations/:id/read
      def read
        @conversation.mark_read_for!(api_user)
        render json: { data: { id: @conversation.id, unread_count: 0 } }
      end

      private

      def set_conversation
        @conversation = Community::Conversation.for_user(api_user).find(params[:id])
      end

      def serialize_conversation(conversation)
        {
          id: conversation.id,
          title: conversation.display_name(api_user),
          is_group: conversation.is_group,
          participants: conversation.users.map { |u| { id: u.public_id, username: u.username } },
          last_message_at: conversation.last_message_at&.iso8601,
          unread_count: conversation.unread_count_for(api_user)
        }
      end

      def serialize_message(message)
        {
          id: message.id,
          conversation_id: message.forum_conversation_id,
          body: message.body,
          author: { id: message.user&.public_id, username: message.user&.username },
          edited: message.edited?,
          created_at: message.created_at&.iso8601
        }
      end
    end
  end
end
