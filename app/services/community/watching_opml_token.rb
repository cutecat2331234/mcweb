# frozen_string_literal: true

module Community
  class WatchingOpmlToken
    InvalidToken = Class.new(StandardError)
    PURPOSE = "watching_opml"

    def self.generate(user)
      Rails.application.message_verifier(PURPOSE).generate(user.id, expires_in: 90.days)
    end

    def self.verify(token)
      Rails.application.message_verifier(PURPOSE).verify(token)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken
    end
  end
end
