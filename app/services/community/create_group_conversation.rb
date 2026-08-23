# frozen_string_literal: true

module Community
  class CreateGroupConversation < ApplicationService
    MAX_PARTICIPANTS = 10

    def initialize(sender:, title:, recipient_usernames:, body:, attachment_ids: [], ip_address: nil)
      @sender = sender
      @title = title.to_s.strip
      @usernames = Array(recipient_usernames).flat_map { |name| name.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq
      @usernames -= [ @sender.username ]
      @body = body.to_s.strip
      @attachment_ids = attachment_ids
      @ip_address = ip_address
    end

    def call
      rate_limit_result = Administration::AbuseRateLimit.call(
        action: :private_message,
        account: @sender,
        ip_address: @ip_address
      )
      return rate_limit_result if rate_limit_result.failure?

      return ServiceResult.failure(error: :group_title_required) if @title.blank?
      return ServiceResult.failure(error: :add_other_participant) if @usernames.empty?
      if @usernames.size >= Community::AddConversationParticipant.max_participants
        return ServiceResult.failure(error: :too_many_participants)
      end
      return ServiceResult.failure(error: :message_too_short) if @body.length < 1
      return ServiceResult.failure(error: :new_members_cannot_send_pm) unless Community::TrustLevel.can_send_pm?(@sender)

      pm_restriction = Community::CheckWarningRestrictions.call(user: @sender, action: :pm)
      return pm_restriction if pm_restriction.failure?

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@sender)
        return ServiceResult.failure(error: :new_members_cannot_post_links)
      end

      link_restriction = Community::CheckWarningRestrictions.call(user: @sender, action: :link)
      return link_restriction if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)

      recipients_by_username = User.where(username: @usernames).index_by(&:username)
      missing = @usernames - recipients_by_username.keys
      if missing.any?
        return ServiceResult.failure(
          error: I18n.t("mcweb.services.errors.users_not_found", names: missing.join(", "))
        )
      end
      recipients = @usernames.map { |username| recipients_by_username.fetch(username) }

      conversation = nil
      message = nil
      invitations = []
      failure = nil
      Identity::UserMutationLock.with_users(users: [ @sender, *recipients ]) do
        conversation = Community::Conversation.create!(
          title: @title,
          is_group: true,
          creator: @sender,
          last_message_at: Time.current
        )
        conversation.participants.create!(user: @sender)

        recipients.each do |recipient|
          eligibility = Community::ConversationInvitationEligibility.call(
            actor: @sender,
            conversation: conversation,
            invitee: recipient
          )
          if eligibility.failure?
            failure = eligibility
            raise ActiveRecord::Rollback
          end

          invitations << conversation.invitations.create!(
            user: recipient,
            invited_by: @sender,
            expires_at: Time.current + Community::ConversationInvitation::DEFAULT_EXPIRY
          )
        end

        message = conversation.messages.create!(user: @sender, body: @body)
        attachment_result = Community::LinkMessageAttachments.call(
          user: @sender,
          message: message,
          attachment_ids: @attachment_ids
        )
        if attachment_result.failure?
          failure = attachment_result
          raise ActiveRecord::Rollback
        end

        conversation.update!(last_message_at: message.created_at)
        conversation.mark_read_for!(@sender)
        conversation.unarchive_all_participants!
      end
      return failure if failure
      return ServiceResult.failure(error: "message_create_failed") unless message&.persisted?

      Community::NotifyPrivateMessage.call(message: message, conversation: conversation)
      invitations.each { |invitation| Community::NotifyConversationInvitation.call(invitation: invitation) }

      ServiceResult.success(conversation: conversation, message: message, invitations: invitations)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end
  end
end
