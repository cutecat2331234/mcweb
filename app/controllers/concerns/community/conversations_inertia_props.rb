# frozen_string_literal: true

module Community
  module ConversationsInertiaProps
    extend ActiveSupport::Concern

    private

    def conversation_show_props(conversation, overrides = {})
      conversation.mark_read_for!(current_user)

      scope = conversation.messages.includes(:user).order(created_at: :asc)
      limit = 50
      last_page = [ (scope.count / limit.to_f).ceil, 1 ].max
      page = params[:page].to_i
      page = last_page if page < 1

      @pagy, messages = pagy(:offset, scope, page: page, limit: limit)
      participants_by_user = conversation.participants.index_by(&:user_id)

      {
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
        invitesLocked: conversation.is_group? && conversation.invites_locked?,
        canManageInvites: conversation.is_group? && conversation.creator_id == current_user.id,
        lockInvitesUrl: lock_invites_forum_conversation_path(conversation),
        unlockInvitesUrl: unlock_invites_forum_conversation_path(conversation),
        currentUsername: current_user.username,
        canSendPm: Community::TrustLevel.can_send_pm?(current_user),
        warningRestrictions: warning_restrictions_props
      }.merge(overrides)
    end

    def group_add_participant_url(conversation)
      return nil unless conversation.is_group?
      return nil unless conversation.participant?(current_user)
      return nil if conversation.participants.count >= Community::AddConversationParticipant.max_participants
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

      if (conversation.invites_locked? || SiteSetting.get("forum.group_pm_creator_only_add", "false") == "true") &&
         !Community::AddConversationParticipant.can_add_member?(current_user, conversation)
        return "仅群主可添加新成员。"
      end

      if conversation.participants.count >= Community::AddConversationParticipant.max_participants
        return "群组人数已满。"
      end

      unless Community::TrustLevel.can_send_pm?(current_user)
        return "新成员暂时无法添加群组成员。"
      end

      pm_restriction = Community::CheckWarningRestrictions.call(user: current_user, action: :pm)
      return pm_restriction.error if pm_restriction.failure?

      nil
    end

    def serialize_conversation(conversation, include_other: false, unread_count: nil, last_message_preview: nil, current_participant: nil)
      other = conversation.other_user(current_user)
      display = conversation.display_name(current_user)
      participant = current_participant || conversation.participants.find_by(user: current_user)

      data = {
        id: conversation.id,
        url: forum_conversation_path(conversation),
        is_group: conversation.is_group?,
        title: conversation.title,
        display_name: display,
        last_message_at: conversation.last_message_at ? l(conversation.last_message_at, format: :short) : nil,
        unread_count: unread_count.nil? ? conversation.unread_count_for(current_user) : unread_count,
        last_message_preview: last_message_preview,
        archived: participant&.archived_at.present?
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
        edited: message.edited?,
        delete_url: (conversation && message.user_id == current_user.id) ? forum_conversation_message_path(conversation, message) : nil,
        edit_url: (conversation && message.user_id == current_user.id) ? forum_conversation_message_path(conversation, message) : nil,
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
