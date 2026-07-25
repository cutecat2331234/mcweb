# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"
require "uri"

module Community
  # A short, opaque, purpose-bound reply address suitable for an RFC 5321 local
  # part. The user and topic stay server-side; only a random nonce and truncated
  # HMAC are sent over email.
  class ForumEmailReplyAddress < ApplicationRecord
    self.table_name = "forum_email_reply_addresses"

    PURPOSE = "forum_topic_reply_v1"
    DEFAULT_TTL = 14.days
    TOKEN_PATTERN = /\A[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{16}\z/
    LOCAL_PART_PREFIX = "reply+"

    belongs_to :user
    belongs_to :topic, -> { unscope(where: :deleted_at) },
      class_name: "Community::Topic",
      foreign_key: :forum_topic_id
    has_many :deliveries,
      class_name: "Community::ForumEmailReplyDelivery",
      foreign_key: :forum_email_reply_address_id,
      dependent: :restrict_with_exception

    validates :purpose, inclusion: { in: [ PURPOSE ] }
    validates :token_digest, presence: true
    validates :expires_at, presence: true

    scope :usable, -> { where(purpose: PURPOSE, revoked_at: nil).where("expires_at > ?", Time.current) }

    class << self
      def issue!(user:, topic:, expires_in: DEFAULT_TTL)
        raise ArgumentError, "User cannot reply to this topic." unless issuable?(user: user, topic: topic)

        5.times do
          token = signed_token
          record = create!(
            user: user,
            topic: topic,
            purpose: PURPOSE,
            token_digest: digest(token),
            expires_at: expires_in.from_now
          )
          return "#{LOCAL_PART_PREFIX}#{token}@#{mailbox_domain}" if record.persisted?
        rescue ActiveRecord::RecordNotUnique
          next
        end

        raise ActiveRecord::RecordNotUnique, "Could not allocate a unique forum reply token."
      end

      def issuable?(user:, topic:)
        return false unless user&.status == "active"
        return false unless user.email_verified?
        return false unless topic
        return false unless Community::ForumAccess.topic_visible?(topic: topic, user: user)
        return false unless topic.status == "published"
        return false if topic.locked? || topic.archived_at.present?
        return false unless topic.section.allowed?(user, :reply)
        return false unless topic.section.trust_allowed?(user, :reply)
        return false unless topic.section.writable_by?(user, :reply)
        return false if Community::Mute.muted?(user, section: topic.section)
        return false if Community::UserSilence.silenced?(user)
        return false if Community::TopicReplyBan.active.exists?(forum_topic_id: topic.id, user_id: user.id)

        true
      end

      def find_by_signed_token(token)
        raw_token = token.to_s
        return unless signed_token?(raw_token)

        find_by(token_digest: digest(raw_token), purpose: PURPOSE)
      end

      def tokens_from(mail)
        Array(mail.to) + Array(mail.cc) + Array(mail.bcc)
      end

      def reply_tokens_from(mail)
        tokens_from(mail).filter_map { |recipient| token_from_recipient(recipient) }.uniq
      end

      def token_from_recipient(recipient)
        address = Mail::Address.new(recipient.to_s)
        return unless address.domain.to_s.casecmp?(mailbox_domain)

        local_part = address.local.to_s
        return unless local_part.downcase.start_with?(LOCAL_PART_PREFIX)

        token = local_part.delete_prefix(LOCAL_PART_PREFIX)
        token if token.match?(TOKEN_PATTERN)
      rescue Mail::Field::ParseError
        nil
      end

      def mailbox_domain
        configured = ENV["MCWEB_INBOUND_EMAIL_DOMAIN"].to_s.strip
        configured_host = host_from(configured)
        return configured_host if configured_host.present?

        public_url_host = host_from(ENV["MCWEB_PUBLIC_URL"])
        return public_url_host if public_url_host.present?

        mailer_host = Rails.application.config.action_mailer.default_url_options[:host].to_s
        host_from(mailer_host).presence || "localhost"
      end

      private

      def signed_token
        nonce = Base64.urlsafe_encode64(SecureRandom.random_bytes(18), padding: false)
        signature = OpenSSL::HMAC.digest("SHA256", signing_key, signing_payload(nonce)).byteslice(0, 12)
        "#{nonce}.#{Base64.urlsafe_encode64(signature, padding: false)}"
      end

      def signed_token?(token)
        return false unless token.match?(TOKEN_PATTERN)

        nonce, supplied_signature = token.split(".", 2)
        expected_signature = OpenSSL::HMAC.digest("SHA256", signing_key, signing_payload(nonce)).byteslice(0, 12)
        decoded_signature = Base64.urlsafe_decode64(supplied_signature)
        ActiveSupport::SecurityUtils.secure_compare(decoded_signature, expected_signature)
      rescue ArgumentError
        false
      end

      def signing_payload(nonce)
        "#{PURPOSE}\0#{nonce}"
      end

      def signing_key
        @signing_key ||= Rails.application.key_generator.generate_key(
          "community/forum-email-reply-address/v1",
          32
        )
      end

      def digest(token)
        Digest::SHA256.hexdigest(token)
      end

      def host_from(value)
        raw = value.to_s.strip
        return if raw.blank?

        uri = URI.parse(raw.include?("://") ? raw : "https://#{raw}")
        uri.host.to_s.downcase.presence
      rescue URI::InvalidURIError
        nil
      end
    end

    def expired?
      expires_at <= Time.current
    end

    def usable?
      purpose == PURPOSE && revoked_at.nil? && !expired?
    end
  end
end
