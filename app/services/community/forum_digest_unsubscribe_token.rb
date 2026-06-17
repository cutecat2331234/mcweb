# frozen_string_literal: true

module Community
  class ForumDigestUnsubscribeToken
    InvalidToken = Class.new(StandardError)
    PURPOSE = "forum_digest_unsubscribe"

    def self.generate(user)
      Rails.application.message_verifier(PURPOSE).generate(user.id, expires_in: 30.days)
    end

    def self.verify(token)
      Rails.application.message_verifier(PURPOSE).verify(token)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken
    end
  end
end
