# frozen_string_literal: true

module Community
  class ConversationsController < ApplicationController
    include Community::WarningRestrictionsSerializable

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
      conversation = Community::Conversation.for_user(current_user).find(params[:id])
      conversation.mark_read_for!(current_user)

      scope = conversation.messages.includes(:user).order(created_at: :asc)
      limit = 50
      last_page = [ (scope.count / limit.to_f).ceil, 1 ].max
      page = params[:page].to_i
      page = last_page if page < 1

      @pagy, messages = pagy(scope, page: page, limit: limit)
      participants_by_user = conversation.participants.index_by(&:user_id)

      render inertia: "Community/Messages/Show", props: {
        conversation: serialize_conversation(conversation, include_other: true),
        messages: messages.map { |msg| serialize_message(msg, conversation: conversation, participants_by_user: participants_by_user) },
        pagination: pagy_props(@pagy),
        participants: conversation.is_group? ? serialize_group_participants(conversation) : [],
        addParticipantUrl: group_add_participant_url(conversation),
        addParticipantRestrictedReason: group_add_restricted_reason(conversation),
        archiveUrl: archive_forum_conversation_path(conversation),
        unarchiveUrl: unarchive_forum_conversation_path(conversation),
        archived: conversation.participants.find_by(user: current_user)&.archived_at.present?,
        muted: conversation.participants.find_by(user: current_user)&.muted_at.present?,
        muteUrl: mute_forum_conversation_path(conversation),
        unmuteUrl: unmute_forum_conversation_path(conversation),
        currentUsername: current_user.username,
        canSendPm: Community::TrustLevel.can_send_pm?(current_user),
        warningRestrictions: warning_restrictions_props
      }
    end

    def new
      render inertia: "Community/Messages/New", props: {
        recipient: params[:to].to_s.presence,
        group: params[:group] == "1",
        canSendPm: Community::TrustLevel.can_send_pm?(current_user),
        warningRestrictions: warning_restrictions_props
      }
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
        redirect_to new_forum_conversation_path(to: conversation_params[:recipient], group: conversation_params[:is_group]),
                    alert: service_error_message(result)
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
      conversation = Community::Conversation.for_user(current_user).find(params[:id])
      result = Community::ToggleConversationMute.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: "已静音此会话。"
      else
        redirect_to forum_conversation_path(conversation), alert: result.error || "操作失败"
      end
    end

    def unmute
      conversation = Community::Conversation.for_user(current_user).find(params[:id])
      result = Community::ToggleConversationMute.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: "已取消静音。"
      else
        redirect_to forum_conversation_path(conversation), alert: result.error || "操作失败"
      end
    end

    private

    def conversation_params
      params.require(:conversation).permit(:recipient, :recipients, :title, :body, :is_group)
    end

    def group_add_participant_url(conversation)
      return nil unless conversation.is_group?
      return nil unless conversation.participant?(current_user)
      return nil if conversation.participants.count >= Community::AddConversationParticipant::MAX_PARTICIPANTS
      return nil unless Community::TrustLevel.can_send_pm?(current_user)

      return nil unless Community::AddConversationParticipant.can_add_member?(current_user, conversation)

      pm_restriction = Community::CheckWarningRestrictions.call(user: current_user, action: :pm)
      return nil if pm_restriction.failure?

      forum_conversation_participants_path(conversation)
    end

    def group_add_restricted_reason(conversation)
      return nil unless conversation.is_group?
      return nil unless conversation.participant?(current_user)
      return nil if group_add_participant_url(conversation)

      if SiteSetting.get("forum.group_pm_creator_only_add", "false") == "true" &&
         !Community::AddConversationParticipant.can_add_member?(current_user, conversation)
        return "仅群主可添加新成员。"
      end

      if conversation.participants.count >= Community::AddConversationParticipant::MAX_PARTICIPANTS
        return "群组人数已满。"
      end

      unless Community::TrustLevel.can_send_pm?(current_user)
        return "新成员暂时无法添加群组成员。"
      end

      pm_restriction = Community::CheckWarningRestrictions.call(user: current_user, action: :pm)
      return pm_restriction.error if pm_restriction.failure?

      nil
    end

    def serialize_conversation(conversation, include_other: false, unread_count: nil)
      other = conversation.other_user(current_user)
      last_message = conversation.messages.max_by(&:created_at)
      display = conversation.display_name(current_user)

      data = {
        id: conversation.id,
        url: forum_conversation_path(conversation),
        is_group: conversation.is_group?,
        title: conversation.title,
        display_name: display,
        last_message_at: conversation.last_message_at ? l(conversation.last_message_at, format: :short) : nil,
        unread_count: unread_count.nil? ? conversation.unread_count_for(current_user) : unread_count,
        last_message_preview: last_message&.body&.truncate(80),
        archived: conversation.participants.find_by(user: current_user)&.archived_at.present?
      }

      if include_other
        if conversation.is_group?
          data[:participants_label] = conversation.participant_names
        elsif other
          data[:other_user] = {
            username: other.username,
            avatar_url: other.avatar_url,
            profile_url: forum_user_path(other.username)
          }
        end
      end

      if conversation.is_group?
        data[:other_username] = display
        data[:avatar_url] = current_user.avatar_url
      elsif other
        data[:other_username] = other.username
        data[:avatar_url] = other.avatar_url
      end

      data
    end

    def serialize_message(message, conversation: nil, participants_by_user: {})
      formatted = Community::FormatPostBody.call(body: message.body)
      body_html = formatted.success? ? formatted.value : ERB::Util.html_escape(message.body)

      read_by = []
      if conversation && message.user_id == current_user.id
        read_by = conversation.participants
          .where.not(user_id: current_user.id)
          .where("last_read_at IS NOT NULL AND last_read_at >= ?", message.created_at)
          .includes(:user)
          .map { |p| p.user.username }
      end

      {
        id: message.id,
        body: message.body,
        body_html: body_html,
        author: message.user.username,
        avatar_url: message.user.avatar_url,
        is_mine: message.user_id == current_user.id,
        created_at: l(message.created_at, format: :short),
        read_by: read_by
      }
    end

    def serialize_group_participants(conversation)
      conversation.users.map do |user|
        can_remove = current_user.id == user.id ||
                     current_user.id == conversation.creator_id ||
                     current_user.permission?("forum.topics.lock")
        {
          username: user.username,
          avatar_url: user.avatar_url,
          is_self: user.id == current_user.id,
          is_creator: user.id == conversation.creator_id,
          remove_url: can_remove ? forum_conversation_participant_path(conversation, user.username) : nil
        }
      end
    end
  end
end
