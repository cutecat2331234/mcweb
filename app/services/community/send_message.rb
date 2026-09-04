# frozen_string_literal: true

module Community
  class SendMessage < ApplicationService
    def initialize(user:, conversation:, body:, attachment_ids: [], ip_address: nil)
      @user = user
      @conversation = conversation
      @body = body.to_s.strip
      @attachment_ids = attachment_ids
      @ip_address = ip_address
    end

    def call
      rate_limit_result = Administration::AbuseRateLimit.call(
        action: :private_message,
        account: @user,
        ip_address: @ip_address
      )
      return rate_limit_result if rate_limit_result.failure?

      return ServiceResult.failure(error: :not_a_participant) unless participant?
      return ServiceResult.failure(error: :message_too_short) if @body.length < 1
      return ServiceResult.failure(error: :new_members_cannot_send_pm) unless Community::TrustLevel.can_send_pm?(@user)

      pm_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :pm)
      return pm_restriction if pm_restriction.failure?

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: :new_members_cannot_post_links)
      end

      link_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :link)
      return link_restriction if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)

      others = @conversation.participants.where.not(user: @user).includes(:user).map(&:user)
      others.each do |other|
        if Community::UserBlock.blocked?(@user, other)
          return ServiceResult.failure(
            error: I18n.t("mcweb.services.errors.cannot_message_user_named", name: other.username)
          )
        end
      end

      message = nil
      attachment_result = nil
      state_result = nil
      Community::Conversation.transaction do
        @user = User.lock.find(@user.id)
        state_result = account_write_access_result
        raise ActiveRecord::Rollback if state_result.failure?

        message = @conversation.messages.create!(user: @user, body: @body)
        attachment_result = Community::LinkMessageAttachments.call(
          user: @user,
          message: message,
          attachment_ids: @attachment_ids
        )
        raise ActiveRecord::Rollback if attachment_result.failure?

        @conversation.update!(last_message_at: message.created_at)
        @conversation.mark_read_for!(@user)
        @conversation.unarchive_all_participants!
        Community::MessageDraft.where(user: @user, conversation: @conversation).delete_all
      end
      return state_result if state_result&.failure?
      return attachment_result if attachment_result&.failure?
      return ServiceResult.failure(error: "message_create_failed") unless message&.persisted?

      Community::NotifyPrivateMessage.call(message: message, conversation: @conversation)

      ServiceResult.success(message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def account_write_access_result
      return ServiceResult.failure(error: :account_deleted) if @user.deleted?
      return ServiceResult.failure(error: :account_banned) if @user.banned?

      ServiceResult.success
    end

    def participant?
      @conversation.participants.exists?(user: @user)
    end
  end
end
