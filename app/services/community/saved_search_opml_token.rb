# frozen_string_literal: true

module Community
  class SavedSearchOpmlToken
    InvalidToken = Class.new(StandardError)
    PURPOSE = "saved_search_opml"

    def self.generate(user)
      Rails.application.message_verifier(PURPOSE).generate(user.id)
    end

    def self.verify(token)
      Rails.application.message_verifier(PURPOSE).verify(token)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken
    end
  end
end
