# frozen_string_literal: true

module Community
  class ConversationsController < ApplicationController
    include Community::WarningRestrictionsSerializable
    include Community::ConversationsInertiaProps

    before_action :require_login

    def index
      include_archived = params[:archived] == "1"
      conversations_scope = Community::Conversation
        .for_user(current_user, include_archived: include_archived)
        .includes(participants: :user, creator: [])
        .ordered

      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        conversation_ids = Community::Message
          .joins(:conversation)
          .merge(Community::Conversation.for_user(current_user, include_archived: include_archived))
          .where("forum_messages.body ILIKE ?", q)
          .distinct
          .pluck(:forum_conversation_id)
        conversations_scope = conversations_scope.where(id: conversation_ids)
      end

      @pagy, conversations = pagy(:offset, conversations_scope, limit: 30)
      conversation_ids = conversations.map(&:id)
      unread_counts = Community::Conversation.unread_counts_for(current_user, conversation_ids)
      last_previews = Community::Conversation.last_message_previews_for(conversation_ids)
      participants_by_conversation = conversations.each_with_object({}) do |conv, memo|
        memo[conv.id] = conv.participants.index_by(&:user_id)
      end

      render inertia: "Community/Messages/Index", props: {
        conversations: conversations.map do |conv|
          serialize_conversation(
            conv,
            unread_count: unread_counts[conv.id],
            last_message_preview: last_previews[conv.id],
            current_participant: participants_by_conversation[conv.id]&.[](current_user.id)
          )
        end,
        pagination: pagy_props(@pagy),
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
        redirect_to forum_conversations_path, notice: t("mcweb.flash.conversation_archived")
      else
        redirect_to forum_conversation_path(conversation), alert: service_error_message(result)
      end
    end

    def unarchive
      conversation = Community::Conversation.for_user(current_user, include_archived: true).find(params[:id])
      result = Community::UnarchiveConversation.call(user: current_user, conversation: conversation)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: t("mcweb.flash.conversation_restored")
      else
        redirect_to forum_conversations_path(archived: 1), alert: service_error_message(result)
      end
    end

    def mute
      conversation = find_accessible_conversation!
      result = Community::ToggleConversationMute.call(user: current_user, conversation: conversation, muted: true)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: t("mcweb.flash.conversation_muted")
      else
        redirect_to forum_conversation_path(conversation), alert: result.error || t("mcweb.flash.operation_failed")
      end
    end

    def unmute
      conversation = find_accessible_conversation!
      result = Community::ToggleConversationMute.call(user: current_user, conversation: conversation, muted: false)

      if result.success?
        redirect_to forum_conversation_path(conversation), notice: t("mcweb.flash.conversation_unmuted")
      else
        redirect_to forum_conversation_path(conversation), alert: result.error || t("mcweb.flash.operation_failed")
      end
    end

    def lock_invites
      set_invites_locked(true)
    end

    def unlock_invites
      set_invites_locked(false)
    end

    private

    def set_invites_locked(locked)
      conversation = find_accessible_conversation!
      unless conversation.is_group? && conversation.creator_id == current_user.id
        return redirect_to forum_conversation_path(conversation), alert: t("mcweb.flash.operation_failed")
      end

      conversation.update!(invites_locked: locked)
      key = locked ? "mcweb.flash.conversation_invites_locked" : "mcweb.flash.conversation_invites_unlocked"
      redirect_to forum_conversation_path(conversation), notice: t(key, default: (locked ? "已锁定邀请" : "已允许成员邀请"))
    end

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
