# frozen_string_literal: true

require "digest"

module Community
  class ProcessForumEmailReply
    def self.call(inbound_email:, mail:, reply_tokens:)
      new(inbound_email: inbound_email, mail: mail, reply_tokens: reply_tokens).call
    end

    def initialize(inbound_email:, mail:, reply_tokens:)
      @inbound_email = inbound_email
      @mail = mail
      @reply_tokens = Array(reply_tokens).uniq
    end

    def call
      Community::ForumEmailReplyDelivery.transaction do
        existing = find_existing_delivery
        next result_for_existing(existing) if existing

        process_delivery(reserve_delivery!)
      end
    rescue ActiveRecord::RecordNotUnique
      delivery = find_existing_delivery
      return result_for_existing(delivery) if delivery

      raise
    end

    private

    def process_delivery(delivery)
      return reject(delivery, "invalid_reply_address") unless @reply_tokens.one?

      reply_address = Community::ForumEmailReplyAddress.find_by_signed_token(@reply_tokens.first)
      return reject(delivery, "invalid_reply_address") unless reply_address

      delivery.update!(reply_address: reply_address)
      return reject(delivery, "expired_reply_address") unless reply_address.usable?

      user = reply_address.user
      topic = reply_address.topic

      return reject(delivery, "account_ineligible") unless eligible_user?(user)
      return reject(delivery, "sender_mismatch") unless sender_matches?(user)
      return reject(delivery, "topic_not_visible") unless Community::ForumAccess.topic_visible?(topic: topic, user: user)
      return reject(delivery, "topic_closed") unless open_topic?(topic)
      return reject(delivery, "reply_not_allowed") unless reply_allowed?(user, topic)

      body = Community::ExtractEmailReplyBody.call(@mail)
      return reject(delivery, "empty_reply") if body.blank?

      post_result = Community::CreatePost.call(user: user, topic: topic, body: body)
      return reject(delivery, "post_rejected") if post_result.failure?

      delivery.update!(status: "posted", post: post_result.value, rejection_reason: nil)
      reply_address.update!(last_used_at: Time.current)
      ServiceResult.success(delivery)
    end

    def reserve_delivery!
      Community::ForumEmailReplyDelivery.create!(
        inbound_email: @inbound_email,
        message_id_digest: message_id_digest,
        status: "processing"
      )
    end

    def find_existing_delivery
      Community::ForumEmailReplyDelivery.find_by(
        action_mailbox_inbound_email_id: @inbound_email.id
      ) || Community::ForumEmailReplyDelivery.find_by(message_id_digest: message_id_digest)
    end

    def result_for_existing(delivery)
      return ServiceResult.failure(error: delivery.rejection_reason, value: delivery) if delivery.rejected?

      ServiceResult.success(delivery)
    end

    def message_id_digest
      @message_id_digest ||= Digest::SHA256.hexdigest(
        @inbound_email.message_id.to_s.strip.downcase
      )
    end

    def eligible_user?(user)
      user.status == "active" && user.email_verified?
    end

    def sender_matches?(user)
      senders = Array(@mail.from).map { |address| normalized_email(address) }.compact.uniq
      senders.one? && ActiveSupport::SecurityUtils.secure_compare(
        senders.first,
        normalized_email(user.email)
      )
    end

    def normalized_email(value)
      Mail::Address.new(value.to_s).address.to_s.strip.downcase.presence
    rescue Mail::Field::ParseError
      nil
    end

    def open_topic?(topic)
      topic.status == "published" &&
        !topic.locked? &&
        topic.archived_at.nil? &&
        topic.deleted_at.nil?
    end

    def reply_allowed?(user, topic)
      section = topic.section
      section.allowed?(user, :reply) &&
        section.trust_allowed?(user, :reply) &&
        section.writable_by?(user, :reply) &&
        !Community::Mute.muted?(user, section: section) &&
        !Community::UserSilence.silenced?(user) &&
        !Community::TopicReplyBan.active.exists?(forum_topic_id: topic.id, user_id: user.id)
    end

    def reject(delivery, reason)
      delivery.update!(status: "rejected", rejection_reason: reason)
      ServiceResult.failure(error: reason, value: delivery)
    end
  end
end
