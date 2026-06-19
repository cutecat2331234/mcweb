# frozen_string_literal: true

module Community
  class ConversationsController < ApplicationController
    include Community::WarningRestrictionsSerializable
    include Community::ConversationsInertiaProps

    before_action :require_login

    def index
      include_archived = params[:archived] == "1"
      conversations = Community::Conversation
        .for_user(current_user, include_archived: include_archived)
        .includes(participants: :user, messages: :user, creator: [])
        .ordered

      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        conversation_ids = Community::Message
          .joins(:conversation)
          .merge(Community::Conversation.for_user(current_user, include_archived: include_archived))
          .where("forum_messages.body ILIKE ?", q)
          .distinct
          .pluck(:forum_conversation_id)
        conversations = conversations.where(id: conversation_ids)
      end

      conversations = conversations.limit(50)
      unread_counts = Community::Conversation.unread_counts_for(current_user, conversations.map(&:id))

      render inertia: "Community/Messages/Index", props: {
        conversations: conversations.map { |conv| serialize_conversation(conv, unread_count: unread_counts[conv.id]) },
        showArchived: include_archived,
        archivedToggleUrl: include_archived ? forum_conversations_path : forum_conversations_path(archived: 1),
        query: params[:q].to_s
      }
    end

    def show
      conversation = find_accessible_conversation!
      render inertia: "Community/Messages/Show", props: conversation_show_props(conversation)
    end

    def new
      render inertia: "Community/Messages/New", props: new_message_form_props
    end

    def create
      if conversation_params[:is_group] == "1" || conversation_params[:is_group] == true
        result = Community::CreateGroupConversation.call(
          sender: current_user,
          title: conversation_params[:title],
          recipient_usernames: conversation_params[:recipients],
          body: conversation_params[:body]
        )
      else
        result = Community::CreateConversation.call(
          sender: current_user,
          recipient_username: conversation_params[:recipient],
          body: conversation_params[:body]
        )
      end

      if result.success?
        redirect_to forum_conversation_path(result.value[:conversation])
      else
        render inertia: "Community/Messages/New",
               status: :unprocessable_entity,
               props: new_message_form_props(form_errors: inertia_form_errors(result, prefix: "conversation"))
      end
    end

    def archive
      conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:id])
      result = Community::ArchiveConversation.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversations_path, notice: "会话已归档。"
      else
        redirect_to forum_conversation_path(conversation), alert: service_error_message(result)
      end
    end

    def unarchive
      conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:id])
      result = Community::UnarchiveConversation.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: "会话已恢复。"
      else
        redirect_to forum_conversations_path(archived: 1), alert: service_error_message(result)
      end
    end

    def mute
      conversation = find_accessible_conversation!
      result = Community::ToggleConversationMute.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: "已静音此会话。"
      else
        redirect_to forum_conversation_path(conversation), alert: result.error || "操作失败"
      end
    end

    def unmute
      conversation = find_accessible_conversation!
      result = Community::ToggleConversationMute.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: "已取消静音。"
      else
        redirect_to forum_conversation_path(conversation), alert: result.error || "操作失败"
      end
    end

    private

    def find_accessible_conversation!
      Community::Conversation.for_user(current_user, include_archived: true).find(params[:id])
    end

    def conversation_params
      params.require(:conversation).permit(:recipient, :recipients, :title, :body, :is_group)
    end

    def new_message_form_props(overrides = {})
      is_group = if overrides.key?(:group)
        overrides[:group]
      elsif params[:group] == "1"
        true
      else
        ActiveModel::Type::Boolean.new.cast(params.dig(:conversation, :is_group)) ||
          params.dig(:conversation, :is_group) == "1"
      end

      {
        recipient: overrides[:recipient] || params[:to].presence || params.dig(:conversation, :recipient).presence,
        recipients: overrides[:recipients] || params.dig(:conversation, :recipients).presence,
        title: overrides[:title] || params.dig(:conversation, :title).presence,
        initialBody: overrides[:initialBody] || params.dig(:conversation, :body).presence,
        group: is_group,
        canSendPm: Community::TrustLevel.can_send_pm?(current_user),
        warningRestrictions: warning_restrictions_props
      }.merge(overrides)
    end
  end
end
