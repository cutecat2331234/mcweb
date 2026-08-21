# frozen_string_literal: true

module Identity
  class CredentialSnapshot
    KEY_PURPOSE = "identity/session-credential-snapshot/v1"

    class << self
      def issue(user)
        return if user&.id.blank? || user.password_digest.blank?

        OpenSSL::HMAC.hexdigest(
          "SHA256",
          signing_key,
          [ user.id, user.password_digest ].join("\0")
        )
      end

      def valid?(user, snapshot)
        expected = issue(user)
        candidate = snapshot.to_s
        return false if expected.blank? || candidate.bytesize != expected.bytesize

        ActiveSupport::SecurityUtils.secure_compare(expected, candidate)
      end

      private

      def signing_key
        @signing_key ||= Rails.application.key_generator.generate_key(KEY_PURPOSE, 32)
      end
    end
  end
end
